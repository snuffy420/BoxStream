' Right-to-left text in display order. Roku draws Hebrew exactly as stored,
' left to right (checked on the TV), so a Hebrew line is reversed here:
' numbers and Latin words keep reading left to right, and brackets turn to
' face the right way.
function visualRtl(row as String) as String
    chars = []
    for k = 1 to Len(row)
        chars.Push(Mid(row, k, 1))
    end for
    mirrors = {"(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{", "<": ">", ">": "<"}
    out = []
    i = chars.Count() - 1
    while i >= 0
        c = chars[i]
        if isLtrChar(c)
            ' A left-to-right run (digits, Latin): copy it in its own order.
            j = i
            while j - 1 >= 0
                prev = chars[j - 1]
                if isLtrChar(prev)
                    j = j - 1
                else if j - 2 >= 0 and (prev = "." or prev = "," or prev = ":" or prev = "/" or prev = "-") and isLtrChar(chars[j - 2])
                    j = j - 1
                else
                    exit while
                end if
            end while
            for k = j to i
                out.Push(chars[k])
            end for
            i = j - 1
        else
            m2 = mirrors[c]
            if m2 <> invalid then out.Push(m2) else out.Push(c)
            i = i - 1
        end if
    end while
    return out.Join("")
end function

function isLtrChar(c as String) as Boolean
    a = Asc(c)
    if a >= 48 and a <= 57 then return true
    if a >= 65 and a <= 90 then return true
    if a >= 97 and a <= 122 then return true
    if a >= 192 and a <= 1423 then return true
    return false
end function
