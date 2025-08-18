local WidgetContainer = require("ui/widget/container/widgetcontainer")

local WordReference = WidgetContainer:extend {
  name = "wordreference",
  is_doc_only = false,
  show_highlight_dialog_button = true,
}

return WordReference
