for _, name in ipairs(uji.modules("uji.builtin.commands")) do
    require(name)
end
