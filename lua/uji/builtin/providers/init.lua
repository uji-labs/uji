for _, name in ipairs(uji.modules("uji.builtin.providers")) do
    require(name)
end
