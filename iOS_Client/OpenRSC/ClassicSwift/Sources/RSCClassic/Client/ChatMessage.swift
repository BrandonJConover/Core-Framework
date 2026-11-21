// Chat compression: port of rsc-c's chat-message.c (nibble-packed by letter frequency).

public enum ChatMessage {
    public static let maxLength = 100
    public static let maxInputLength = 80
    static let charMap: [UInt8] = Array(" etaoihnsrdlumwcyfgpbvkxjqz0123456789 !?.,:;()-&*\\'@#+= $%\"[]`".utf8)

    public static func decode(_ buffer: [UInt8], offset: Int, length: Int) -> String {
        var out = [UInt8]()
        var leftShift = -1
        var o = offset
        func push(_ mapIndex: Int) -> Bool {
            if out.count >= maxLength { return false }
            if leftShift == -1 {
                if mapIndex < 13 { out.append(charMap[mapIndex]) } else { leftShift = mapIndex }
            } else {
                let i = (leftShift << 4) + mapIndex - 195
                out.append(i >= 0 && i < charMap.count ? charMap[i] : 32)
                leftShift = -1
            }
            return true
        }
        for _ in 0..<length {
            let current = Int(buffer[o])
            o += 1
            if !push(current >> 4 & 0xf) { break }
            if !push(current & 0xf) { break }
        }
        var flag = true
        for i in 0..<out.count {
            let c = out[i]
            if i > 4 && c == 64 { out[i] = 32 }
            if c == 37 { out[i] = 32 }
            if flag && c >= 97 && c <= 122 {
                out[i] = out[i] &- 32
                flag = false
            }
            if c == 46 || c == 33 { flag = true }
        }
        return String(decoding: out, as: Latin1.self)
    }

    public static func encode(_ message: String) -> [UInt8] {
        let bytes = Array(Surface.bytes(message).prefix(maxInputLength))
        var out = [UInt8]()
        var leftShift = -1
        for b in bytes {
            let c = (b >= 65 && b <= 90) ? b + 32 : b
            var index = charMap.firstIndex(of: c) ?? 0
            if index > 12 { index += 195 }
            if leftShift == -1 {
                if index < 13 { leftShift = index } else { out.append(UInt8(index & 0xff)) }
            } else if index < 13 {
                out.append(UInt8(((leftShift << 4) + index) & 0xff))
                leftShift = -1
            } else {
                out.append(UInt8(((leftShift << 4) + (index >> 4)) & 0xff))
                leftShift = index & 0xf
            }
        }
        if leftShift != -1 { out.append(UInt8((leftShift << 4) & 0xff)) }
        return out
    }
}
