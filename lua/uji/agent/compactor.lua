local model = require("uji.model")
local tokens = require("uji.agent.tokens")
local view = require("uji.agent.view")

local MAX_INPUT = 200000

local FORMAT = [[## Goal
[What the user is trying to accomplish. Multiple items if the session covers several tasks.]

## Constraints & Preferences
- [Constraints, preferences or requirements the user stated, or "(none)"]

## Progress
### Done
- [x] [Completed work]
### In Progress
- [ ] [Current work]
### Blocked
- [What is preventing progress, or "(none)"]

## Key Decisions
- **[Decision]**: [Brief rationale]

## Next Steps
1. [Ordered list of what should happen next]

## Critical Context
- [Data, examples or references needed to continue, or "(none)"]

Keep each section concise. Preserve exact file paths, function names, commands and error strings verbatim.]]

local PROMPT = "You compact coding sessions. The messages above are a conversation to "
    .. "summarise. Write a structured checkpoint that another agent will use to continue the work "
    .. "without the original transcript. Do not invent anything that is not in the transcript. "
    .. "Reply with the summary alone, no preamble.\n\n"
    .. "Use this EXACT format:\n\n"

local UPDATE_PROMPT = "You maintain a rolling checkpoint of a coding session. The "
    .. "existing checkpoint is in <previous-summary> tags; the messages after it are NEW activity "
    .. "to fold in.\n\n"
    .. "RULES:\n"
    .. "- PRESERVE every fact from the previous checkpoint unless it became wrong.\n"
    .. "- MOVE items from \"In Progress\" to \"Done\" as they complete.\n"
    .. "- UPDATE \"Next Steps\" to reflect the current state.\n"
    .. "- PRESERVE exact file paths, function names, commands and error strings.\n"
    .. "- Drop items only when they are no longer relevant.\n\n"
    .. "Reply with the updated checkpoint alone, no preamble.\n\n"
    .. "Use this EXACT format:\n\n"

local LABELS = {
    user = "user",
    assistant = "assistant",
    system = "system",
    error = "error",
    compaction = "earlier summary",
}

local M = {}

function M.transcript(messages)
    local chunks = {}
    local budget = MAX_INPUT
    for index = #messages, 1, -1 do
        local message = messages[index]
        local kind = message.type
        if kind ~= "shell" and kind ~= "context" then
            local label = kind == "tool" and message.name or LABELS[kind]
            local text = tokens.text(message)
            if text:find("%S") then
                local chunk = "[" .. label .. "] " .. text .. "\n\n"
                local size = tokens.chars(chunk)
                if size > budget then
                    break
                end
                budget = budget - size
                chunks[#chunks + 1] = chunk
            end
        end
    end
    local ordered = {}
    for index = #chunks, 1, -1 do
        ordered[#ordered + 1] = chunks[index]
    end
    return table.concat(ordered)
end

function M.generate(messages, previous)
    local transcript = M.transcript(messages)
    if not transcript:find("%S") then
        return nil
    end
    local instructions, text = PROMPT, transcript
    if previous then
        instructions = UPDATE_PROMPT
        text = "<previous-summary>\n" .. previous .. "\n</previous-summary>\n\n" .. transcript
    end
    local answer = model.generate({
        system = instructions .. FORMAT,
        messages = { { type = "user", text = text } },
    })
    if not answer then
        return nil
    end
    local summary = (answer.text or ""):match("^%s*(.-)%s*$")
    if summary == "" then
        return nil
    end
    return { summary = summary, usage = answer.usage }
end

function M.fold(messages, budget, keep_recent)
    if tokens.messages(messages) < model.usable(budget) then
        return nil
    end
    local at = view.cut_index(messages, keep_recent)
    if not at then
        return nil
    end
    local carried = view.previous_files(messages[1])
    local previous = view.previous_summary(messages[1])
    local skip = previous and 1 or 0
    local head = {}
    for index = 1 + skip, at - 1 do
        head[#head + 1] = messages[index]
    end
    local files = view.merge_files(view.files_touched(head), carried)
    local done = M.generate(head, previous)
    if not done then
        return nil
    end
    local folded = { view.summary_message(done.summary, files) }
    for index = at, #messages do
        folded[#folded + 1] = messages[index]
    end
    return { messages = folded, summary = done.summary, usage = done.usage, count = #head }
end

return M
