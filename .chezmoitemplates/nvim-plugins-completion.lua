-- Accept the completion item with <Tab> instead of <Enter>.
--
-- The "enter" preset binds <CR> to { "accept", "fallback" } and <Tab> to
-- { "snippet_forward", "fallback" }; the two entries below override exactly
-- those keys and leave the rest of the preset alone.
return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        preset = "enter",
        ["<Tab>"] = { "select_and_accept", "fallback" },
        ["<CR>"] = { "fallback" },
      },
    },
  },
}
