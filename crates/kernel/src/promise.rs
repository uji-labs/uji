use std::cell::RefCell;

use mlua::{Function, Lua, MultiValue, UserData, UserDataFields, UserDataMethods, Value};
use tokio::sync::oneshot;

#[derive(Default)]
pub(crate) struct Promise {
    values: RefCell<Option<Vec<Value>>>,
    waiters: RefCell<Vec<oneshot::Sender<()>>>,
}

impl Promise {
    fn settled(&self) -> Option<Vec<Value>> {
        self.values.borrow().clone()
    }

    fn resolve(&self, values: MultiValue) -> bool {
        if self.values.borrow().is_some() {
            return false;
        }
        self.values.replace(Some(values.into_vec()));
        self.waiters.take().into_iter().for_each(|waiter| {
            let _ = waiter.send(());
        });
        true
    }
}

impl UserData for Promise {
    fn add_fields<F: UserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("settled", |_, promise| {
            Ok(promise.values.borrow().is_some())
        });
    }

    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("resolve", |_, promise, values: MultiValue| {
            Ok(promise.resolve(values))
        });
        methods.add_async_method("await", |_, promise, ()| async move {
            if let Some(values) = promise.settled() {
                return Ok(MultiValue::from_vec(values));
            }
            let (sender, receiver) = oneshot::channel();
            promise.waiters.borrow_mut().push(sender);
            receiver
                .await
                .map_err(|_| mlua::Error::runtime("the promise was dropped"))?;
            Ok(MultiValue::from_vec(promise.settled().unwrap_or_default()))
        });
    }
}

pub(crate) fn constructor(lua: &Lua) -> mlua::Result<Function> {
    lua.create_function(|_, ()| Ok(Promise::default()))
}
