sub init()
    m.top.functionName = "check"
end sub

' request: {url, code}. result: {ok, error} (error is the message to show).
sub check()
    req = m.top.request
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(req.url + "/ping")
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.AddHeader("X-Helper-Token", req.code)
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.AsyncGetToString()
    event = Wait(15000, port)
    text = "Can't reach the helper. Check the address."
    if type(event) = "roUrlEvent"
        code = event.GetResponseCode()
        if code = 200 and Instr(1, event.GetString(), "true") > 0 then text = "Helper connected"
        if code = 403 then text = "The helper refused the pairing code"
    end if
    m.top.result = {ok: text = "Helper connected", error: text}
end sub
