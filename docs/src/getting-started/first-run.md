# First run

Start uji in the directory you want to work on.

```sh
cd ~/code/project
uji
```

## Signing in

Type `/login` and pick a provider from the list.

- Anthropic and OpenAI ask how you want to sign in. "Subscription (sign in
  with browser)" opens the provider's sign-in page, and "API key" asks for a
  key.
- A provider that needs a key asks for it. The prompt names the environment
  variable uji also reads, such as `ANTHROPIC_API_KEY`, and pressing Enter on
  an empty prompt uses that variable instead.
- Custom asks for the `base_url` and model of a server that takes OpenAI chat
  requests.

uji saves keys in `auth.toml` in the
[data directory](../configuration/files.md), readable only by you. To keep them
in the system keychain instead, call
[`uji.auth.configure`](../api/auth.md) in your config.

## Choosing a model

`/models` lists the models of every provider you are signed in to. `/effort`
sets how much the model reasons, from the levels that model accepts.

## Working with the model

- Enter sends your message. Shift+Enter, Alt+Enter or Ctrl+J start a new line.
- A message you send while the model works waits, and goes out when the turn
  ends.
- Esc clears the input line. On an empty line, Esc stops the turn.
- A line that starts with `!` runs in your shell, in the session's directory.
  Its output shows in the transcript, and the model does not see it.
- When a tool call needs your approval, `y` lets it run. `n` or Esc refuses
  it, and you can then tell the model what to do instead.

## Sending images

Ctrl+V attaches the image on the clipboard, or pastes its text when it holds
no image. Pasting the path of an image file attaches that file, which is what
dragging a file into most terminals does, and `@screenshot.png` in a message
attaches the file when you send it.

Each attached image shows as `[image #1]` on the input line, and deleting the
marker drops the image. uji takes PNG, JPEG, GIF and WebP files. It turns
photos upright and scales images down to 1568 pixels on their long side, then
to a smaller size or JPEG when they would still pass 5 MB.

A request carries the 20 newest images of the conversation, and a note takes
the place of older ones. A model that takes no images gets the text with the
same kind of note. uji knows this for most built-in models, and learns it for
others the first time a model refuses a request with images.

The model can open images on its own as well. `read_file` on a PNG, JPEG, GIF
or WebP file in the working directory gives it the image.

uji saves every conversation as a session.
[Commands](commands.md#running-uji) shows how to go back to one.
