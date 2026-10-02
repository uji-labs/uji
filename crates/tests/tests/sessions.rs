use std::error::Error;
use uji_tests::Sandbox;

fn sandbox(name: &str) -> Result<Sandbox, Box<dyn Error>> {
    Ok(Sandbox::new(name)?)
}

#[test]
fn blank_sessions_are_transient_and_first_messages_survive_restart() -> Result<(), Box<dyn Error>> {
    let sandbox = sandbox("lazy-sessions")?;
    let seen = sandbox.probe(
        r#"
        local app = require('uji.core.app')
        local store, session = app.store, app.session
        assert(session.pending and #store:sessions() == 0)
        session:rename('a draft')
        assert(#store.db:query('SELECT id FROM sessions') == 0)
        local entry = assert(session:append({ type='user', text='saved text' }))
        assert(not session.pending and #store:sessions() == 1)
        assert(store:latest(session.directory).id == session.id)
        emit({ id=session.id, message_id=entry.id })
    "#,
    )?;
    let id = seen[0]["id"].as_str().ok_or("missing id")?;
    let message_id = seen[0]["message_id"].as_str().ok_or("missing message id")?;
    let script = format!(
        r#"
        local app = require('uji.core.app')
        assert(app.session.pending)
        assert(#app.store:sessions() == 1)
        local saved = assert(app.store:session('{id}'))
        assert(saved.title == 'a draft' and not saved.pending)
        assert(saved:entries()[1].id == '{message_id}')
        assert(saved:messages()[1].text == 'saved text')
        assert(app.store:latest(saved.directory).id == saved.id)
        emit(true)
    "#
    );
    sandbox.probe(&script)?;
    Ok(())
}

#[test]
fn rejected_first_message_publishes_nothing() -> Result<(), Box<dyn Error>> {
    sandbox("session-rollback")?.probe(
        r#"
        local core = function(name) return require('uji.core.'..name) end
        local app, event = core('app'), core('event')
        local db, session = app.store.db, app.session
        local events = 0
        event.on('message_appended', function() events = events+1 end)
        assert(db:exec([[CREATE TRIGGER reject_first BEFORE INSERT ON messages
            BEGIN SELECT RAISE(ABORT, 'rejected message'); END]]))
        local entry, err = session:append({type='user', text='must not persist'})
        assert(not entry and err:find('rejected message', 1, true))
        assert(session.pending and #session:entries() == 0 and events == 0)
        assert(#db:query('SELECT id FROM sessions') == 0)
        assert(#db:query('SELECT id FROM messages') == 0)
        assert(db:exec('DROP TRIGGER reject_first'))
        assert(session:append({type='shell', text='saved shell result'}).seq == 1)
        assert(not session.pending and events == 1)
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn child_history_and_deletion_preserve_other_sessions() -> Result<(), Box<dyn Error>> {
    sandbox("session-children")?.probe(
        r#"
        local store = require('uji.core.app').store
        local parent = store:create_session('parent')
        local child = parent:child('child')
        local other = store:create_session('other')
        assert(#store.db:query('SELECT id FROM sessions') == 0)
        assert(child:append({type='user',text='child work'}))
        assert(not child.pending and not parent.pending)
        assert(store:has_history(parent.id) and #store:tree(parent.id) == 2)
        assert(store:latest(parent.directory).id == parent.id)
        assert(other:append({type='error',text='retain errors'}))
        assert(store:delete(parent.id))
        assert(not store:session(parent.id) and not store:session(child.id))
        assert(store:session(other.id):messages()[1].text == 'retain errors')
        assert(#store.db:query('SELECT id FROM messages') == 1)
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn legacy_empty_sessions_remain_deletable_but_never_win_latest() -> Result<(), Box<dyn Error>> {
    sandbox("session-legacy")?.probe(
        r#"
        local store, sys = require('uji.core.app').store, require('uji.sys')
        local saved = store:create_session('saved')
        assert(saved:append({type='user',text='keep'}))
        assert(store.db:exec([[INSERT INTO sessions
            (id,title,directory,time_created,time_updated) VALUES (?,?,?,?,?)]],
            {'legacy-empty','untitled',saved.directory,sys.os.now(),sys.os.now()+10000}))
        assert(#store:sessions() == 2)
        assert(not store:has_history('legacy-empty'))
        assert(store:latest(saved.directory).id == saved.id)
        assert(store:delete('legacy-empty') and #store:sessions() == 1)
        assert(store:session(saved.id):messages()[1].text == 'keep')
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn failed_writes_stop_inference_and_reload_keeps_drafts() -> Result<(), Box<dyn Error>> {
    sandbox("session-plugin")?.probe(
        r#"
        local core = function(name) return require('uji.core.'..name) end
        local app, sys = core('app'), require('uji.sys')
        local calls = 0
        local api = { stream=function(_, reply, modern_reply)
            reply = modern_reply or reply
            calls=calls+1; reply.done({text='done',tool_calls={}})
        end }
        local spec = { id='session-fixture',name='Fixture',
            base_url='https://fixture.invalid',auth_env={'FIXTURE_KEY'},models={'m'} }
        spec.api=api
        uji.provider.add(spec)
        core('auth').save_key('session-fixture', 'synthetic-test-key')
        local model = core('model')
        model.set_setting('llm.provider','session-fixture')
        model.set_setting('llm.model','m'); model.resolve()
        app.session:rename('fixture')
        assert(app.store.db:exec([[CREATE TRIGGER reject_first BEFORE INSERT ON messages
            BEGIN SELECT RAISE(ABORT, 'rejected user'); END]]))
        local ok = pcall(uji.session.submit, 'do not send')
        sys.sleep(0)
        assert(not ok and calls == 0 and app.session.pending)
        assert(#app.store:sessions() == 0 and #app.session:messages() == 0)
        local restarted
        sys.os.restart = function(options) restarted=options end
        uji.input.set('unsent draft')
        core('config').reload()
        assert(restarted.args[2] == 'new')
        assert(sys.json.decode(restarted.carry).draft == 'unsent draft')
        local flags = {}
        for index=3,#restarted.args,2 do flags[restarted.args[index]]=restarted.args[index+1] end
        assert(flags['--db'] == app.flags.db)
        assert(flags['--config-dir'] == app.flags['config-dir'])
        assert(flags['--data-dir'] == app.flags['data-dir'])
        assert(app.store.db:exec('DROP TRIGGER reject_first'))
        local finished = sys.promise()
        core('event').on('turn_finished',function() finished:resolve(true) end)
        uji.session.submit('now save')
        finished:await()
        assert(calls == 1 and not app.session.pending)
        assert(app.session:messages()[2].type=='assistant' and app.session:messages()[2].text=='done')
        assert(#app.store:sessions() == 1 and #app.session:messages() == 2)
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn switching_preserves_drafts_and_blocks_running_shells() -> Result<(), Box<dyn Error>> {
    sandbox("session-drafts")?.probe(
        r#"
        local core = function(name) return require('uji.core.'..name) end
        local app, sys = core('app'), require('uji.sys')
        local manager, ui = core('ui.sessions'), core('ui')
        local saved = app.store:create_session('target')
        assert(saved:append({type='user',text='target history'}))
        local restarted, opened = nil, false
        sys.os.restart = function(options) restarted=options end
        ui.ask = function() opened=true end
        app.agent.shell = {}
        core('command').run('sessions')
        assert(not opened)
        assert(not pcall(manager.switch,saved) and not restarted)
        app.agent.shell = nil
        ui.composer:paste('first line\nsecond line')
        manager.switch(saved)
        assert(sys.json.decode(restarted.carry).draft == 'first line\nsecond line')
        restarted = nil
        ui.composer:attach({name='fixture image'})
        local draft = ui.composer:text()
        assert(not pcall(manager.switch,saved) and not restarted)
        assert(not pcall(core('config').reload) and not restarted)
        assert(ui.composer:text() == draft and #ui.composer.pastes:images(draft) == 1)
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn failed_compaction_and_interrupt_writes_leave_the_agent_idle() -> Result<(), Box<dyn Error>> {
    sandbox("session-operation-failures")?.probe(
        r#"
        local core = function(name) return require('uji.core.'..name) end
        local app, sys, event = core('app'), require('uji.sys'), core('event')
        local agent, db = app.agent, app.store.db
        app.session:rename('fixture')
        assert(app.session:append({type='user',text=string.rep('old ',100)}))
        assert(app.session:append({type='user',text='recent'}))
        assert(db:exec([[CREATE TRIGGER reject_compaction BEFORE INSERT ON messages
            WHEN NEW.type='compaction' BEGIN SELECT RAISE(ABORT,'compaction rejected'); END]]))
        core('agent.compactor').generate = function() return 'summary', {} end
        local idle = sys.promise()
        event.on('status_changed',function() if not agent:working() then idle:resolve(true) end end)
        assert(agent:compact(0))
        idle:await()
        assert(not agent:working() and #app.session:messages() == 2)
        assert(db:exec('DROP TRIGGER reject_compaction'))
        local entered, reply = sys.promise(), nil
        local api = {stream=function(_,out,modern_out) reply=modern_out or out; entered:resolve(true) end}
        local spec = {id='interrupt-fixture',name='Fixture',
            base_url='https://fixture.invalid',auth_env={'FIXTURE_KEY'},models={'m'}}
        spec.api=api
        uji.provider.add(spec)
        core('auth').save_key('interrupt-fixture','synthetic-test-key')
        local model = core('model')
        model.set_setting('llm.provider','interrupt-fixture'); model.set_setting('llm.model','m'); model.resolve()
        assert(db:exec([[CREATE TRIGGER reject_interrupt BEFORE INSERT ON messages
            WHEN NEW.type='error' BEGIN SELECT RAISE(ABORT,'interrupt rejected'); END]]))
        uji.session.submit('wait')
        entered:await()
        assert(agent:working())
        assert(not pcall(function() agent:interrupt() end))
        assert(not agent:working())
        reply.done({text='late answer',tool_calls={}})
        sys.sleep(0)
        assert(#app.session:messages() == 3)
        assert(db:exec('DROP TRIGGER reject_interrupt'))
        assert(app.session:append({type='user',text='can persist again'}))
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn failed_automatic_compaction_cannot_discard_queued_input() -> Result<(), Box<dyn Error>> {
    sandbox("session-queued-input")?.probe(
        r#"
        local core = function(name) return require('uji.core.'..name) end
        local app, sys, event = core('app'), require('uji.sys'), core('event')
        local agent, db, manager = app.agent, app.store.db, core('ui.sessions')
        app.session:rename('fixture')
        assert(app.session:append({type='user',text=string.rep('old ',300)}))
        assert(app.session:append({type='user',text='recent'}))
        local target=app.store:create_session('target')
        assert(target:append({type='user',text='other history'}))
        local api={stream=function() error('inference must not start') end}
        local spec={id='queued-fixture',name='Fixture',base_url='https://fixture.invalid',
            models={{id='m',context=64,output=16}}}
        spec.api=api
        uji.provider.add(spec)
        local model=core('model')
        model.set_setting('llm.provider','queued-fixture'); model.set_setting('llm.model','m'); model.resolve()
        uji.context.configure({compaction={keep_recent=0,reserve=0}})
        assert(db:exec([[CREATE TRIGGER reject_auto_compaction BEFORE INSERT ON messages
            WHEN NEW.type='compaction' BEGIN SELECT RAISE(ABORT,'compaction rejected'); END]]))
        core('agent.compactor').generate=function() return 'summary',{} end
        local idle=sys.promise()
        event.on('status_changed',function() if not agent:working() then idle:resolve(true) end end)
        uji.session.submit('queued input must survive')
        idle:await()
        assert(not agent:working() and #app.session:messages()==2)
        assert(#agent.queue==1 and agent.queue[1].text=='queued input must survive')
        local restarted,opened=false,false
        sys.os.restart=function() restarted=true end
        core('ui').ask=function() opened=true end
        assert(not pcall(manager.switch,target))
        core('config').reload()
        core('command').run('sessions')
        assert(not restarted and not opened)
        assert(#agent.queue==1 and agent.queue[1].text=='queued input must survive')
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn rejected_steering_keeps_queued_text_and_images_for_retry() -> Result<(), Box<dyn Error>> {
    sandbox("session-steering-retry")?.probe(
        r#"
        local app, sys = require('uji.core.app'), require('uji.sys')
        local agent, db = app.agent, app.store.db
        local image={media_type='image/png',data='opaque-image',name='queued.png'}
        agent:enqueue('queued text', {image})
        assert(db:exec([[CREATE TRIGGER reject_queued BEFORE INSERT ON messages
            WHEN NEW.type='user' BEGIN SELECT RAISE(ABORT,'queued write rejected'); END]]))
        assert(not pcall(agent.steer,agent))
        assert(#agent.queue==1 and agent.queue[1].text=='queued text')
        assert(agent.queue[1].images[1].data=='opaque-image')
        assert(#app.session:messages()==0 and app.session.pending)
        assert(db:exec('DROP TRIGGER reject_queued'))
        local message=agent:steer()
        assert(message.text=='queued text' and message.images[1].data=='opaque-image')
        assert(#agent.queue==0 and #app.session:messages()==1)
        local loaded=assert(app.store:session(app.session.id))
        assert(loaded:messages()[1].images[1].data=='opaque-image')
        emit(true)
    "#,
    )?;
    Ok(())
}

#[test]
fn queued_submission_requires_a_committed_user_message() -> Result<(), Box<dyn Error>> {
    sandbox("session-submit-retry")?.probe(
        r#"
        local app, sys, event = require('uji.core.app'),require('uji.sys'),require('uji.core.event')
        local agent, db = app.agent, app.store.db
        local calls=0
        uji.provider.add({id='queued-retry',name='Fixture',base_url='https://fixture.invalid',
            auth_env={'FIXTURE_KEY'},models={{id='m',images=true,context=10000,output=1000}},
            api={stream=function(_,request,reply)
                calls=calls+1
                assert(request.messages[1].images[1].data=='opaque-image')
                reply.fail({kind='provider',message='failure after committed input'})
            end}})
        require('uji.core.auth').save_key('queued-retry','synthetic-test-key')
        local model=require('uji.core.model')
        model.set_setting('llm.provider','queued-retry');model.set_setting('llm.model','m');model.resolve()
        app.session:rename('fixture')
        agent:enqueue('queued text',{{media_type='image/png',data='opaque-image',name='queued.png'}})
        assert(db:exec([[CREATE TRIGGER reject_queued BEFORE INSERT ON messages
            WHEN NEW.type='user' BEGIN SELECT RAISE(ABORT,'queued write rejected'); END]]))
        assert(not pcall(agent.send_queued,agent))
        assert(calls==0 and #agent.queue==1 and agent.queue[1].images[1].data=='opaque-image')
        assert(#app.session:messages()==0 and app.session.pending)
        assert(db:exec('DROP TRIGGER reject_queued'))
        local finished=sys.promise()
        event.on('turn_finished',function() finished:resolve(true) end)
        agent:send_queued();finished:await()
        assert(calls==1 and #agent.queue==0)
        assert(#app.session:messages()==2 and app.session:messages()[1].text=='queued text')
        assert(app.session:messages()[1].images[1].data=='opaque-image')
        assert(app.session:messages()[2].type=='error' and not agent:working())
        emit(true)
    "#,
    )?;
    Ok(())
}
