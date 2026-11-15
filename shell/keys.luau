-- The Keys scene (keys.plm): the frame's logic writes the panels' text fields through this event (it reads them as `Keys.<field>`).
on("set_text", function(v)
    if type(v) == "table" and type(v.name) == "string" then text[v.name] = tostring(v.value or "") end
end)
