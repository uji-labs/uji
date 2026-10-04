local scenario = require("scenario")

scenario.open()
scenario.history(125)

bench("open a 500 message session", scenario.cold)

bench("scroll to the top of 500 messages", scenario.scroll_to_top)
