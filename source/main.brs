sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.Show()
    scene.SignalBeacon("AppLaunchComplete")
    while true
        message = Wait(0, port)
        if type(message) = "roSGScreenEvent"
            if message.IsScreenClosed() then return
        end if
    end while
end sub
