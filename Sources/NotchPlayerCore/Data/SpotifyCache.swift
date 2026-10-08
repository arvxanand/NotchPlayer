import Foundation

/// A private playlist's name and cover, read from Spotify's own database on
/// this Mac.
///
/// **Nothing public describes a private playlist.** The link preview, the web
/// page and the embed page all answer "not found" or a login page, even with
/// the `pt=` token Spotify puts in a private share link (checked 9 Oct 2026).
/// The desktop app keeps the user's playlists in a LevelDB under
/// `PersistentCache/Users/<id>-user/primary.ldb`, keyed
/// `!pl#slc#<len><uri>#`, and its value is a protobuf whose field 3 holds the
/// name (1) and the picture's image id (3).
///
/// **Undocumented, so it is a fallback, never the only path.** Anything
/// unexpected -- a new layout, a missing file, a compacted-away record -- is
/// nil, and the pick is added as "Playlist" with a note, as before. Read-only;
/// Spotify holds the lock, and nothing here writes or locks.
///
/// Measured on the owner's Mac, Spotify 1.3.3: 193 tables, 323MB. Each table
/// is asked through its own index, so a lookup reads one block per table
/// rather than the database.
public enum SpotifyCache {
    public struct Playlist: Equatable, Sendable {
        public let name: String
        public let cover: URL?
    }

    public static func playlist(_ uri: String, home: String = NSHomeDirectory()) -> Playlist? {
        guard uri.hasPrefix("spotify:playlist:"), uri.utf8.count < 128 else { return nil }
        let users = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Spotify/PersistentCache/Users")
        let folders = (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
        let key = Array("!pl#slc#".utf8) + [UInt8(uri.utf8.count)] + Array(uri.utf8) + Array("#".utf8)
        for folder in folders {
            let db = folder.appendingPathComponent("primary.ldb")
            if let value = newest(key, in: db), let found = parse(value) { return found }
        }
        return nil
    }

    // MARK: - The record

    /// Field 3 of the value: its 1 is the name, its 3 the picture's id.
    static func parse(_ value: [UInt8]) -> Playlist? {
        guard let attributes = Proto.field(3, in: value[...]),
              let nameBytes = Proto.field(1, in: attributes),
              let name = String(bytes: nameBytes, encoding: .utf8), !name.isEmpty else { return nil }
        let cover = Proto.field(3, in: attributes).flatMap { id -> URL? in
            // ab67706c… is a playlist picture; 20 bytes is the id's size.
            guard id.count == 20 else { return nil }
            return URL(string: "https://i.scdn.co/image/" + id.map { String(format: "%02x", $0) }.joined())
        }
        return Playlist(name: name, cover: cover)
    }

    // MARK: - LevelDB, read-only

    /// The value with the highest sequence number for `key`, across the tables
    /// and the log; nil if the newest entry is a deletion, or there is none.
    static func newest(_ key: [UInt8], in db: URL) -> [UInt8]? {
        let files = (try? FileManager.default.contentsOfDirectory(at: db, includingPropertiesForKeys: nil)) ?? []
        var best: (seq: UInt64, value: [UInt8]?)?
        func offer(_ seq: UInt64, _ value: [UInt8]?) {
            if best == nil || seq > best!.seq { best = (seq, value) }
        }
        for file in files where file.pathExtension == "ldb" {
            if let hit = Table.lookup(key, in: file) { offer(hit.seq, hit.value) }
        }
        for file in files where file.pathExtension == "log" {
            if let data = try? Data(contentsOf: file) {
                for hit in Log.entries([UInt8](data), key: key) { offer(hit.seq, hit.value) }
            }
        }
        return best?.value
    }

    enum Table {
        static let magic: UInt64 = 0xdb4775248b80fb57

        static func lookup(_ key: [UInt8], in url: URL) -> (seq: UInt64, value: [UInt8]?)? {
            guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? file.close() }
            guard let size = try? file.seekToEnd(), size >= 48,
                  let footer = read(file, at: size - 48, count: 48),
                  UInt64(littleEndian: footer[40..<48].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }) == magic
            else { return nil }
            var i = footer.startIndex
            guard let _ = Varint.read(footer, &i), let _ = Varint.read(footer, &i),
                  let indexOffset = Varint.read(footer, &i), let indexSize = Varint.read(footer, &i),
                  let index = block(file, offset: indexOffset, size: indexSize) else { return nil }
            // The first block whose last key is at or past ours is the only
            // one it can be in.
            for (separator, handle) in Block.entries(index) where userKey(separator).lexicographicallyPrecedes(key) == false {
                var j = handle.startIndex
                guard let offset = Varint.read(handle, &j), let length = Varint.read(handle, &j),
                      let data = block(file, offset: offset, size: length) else { return nil }
                var hit: (seq: UInt64, value: [UInt8]?)?
                for (stored, value) in Block.entries(data) where stored.count >= 8 && Array(userKey(stored)) == key {
                    let tag = stored.suffix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
                    let seq = tag >> 8
                    if hit == nil || seq > hit!.seq { hit = (seq, tag & 0xff == 1 ? Array(value) : nil) }
                }
                return hit
            }
            return nil
        }

        static func userKey(_ stored: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
            stored.dropLast(min(8, stored.count))
        }

        /// A block and its 5-byte trailer: a compression byte (0 none, 1
        /// Snappy) and a checksum this does not check -- a bad block fails to
        /// parse, which is nil either way.
        static func block(_ file: FileHandle, offset: UInt64, size: UInt64) -> [UInt8]? {
            guard size < 64 << 20, let raw = read(file, at: offset, count: Int(size) + 1) else { return nil }
            let body = Array(raw.dropLast())
            switch raw.last {
            case 0: return body
            case 1: return Snappy.decompress(body)
            default: return nil
            }
        }

        static func read(_ file: FileHandle, at offset: UInt64, count: Int) -> [UInt8]? {
            guard (try? file.seek(toOffset: offset)) != nil,
                  let data = try? file.read(upToCount: count), data.count == count else { return nil }
            return [UInt8](data)
        }
    }

    /// Prefix-compressed entries, then a restart array this does not need.
    enum Block {
        static func entries(_ block: [UInt8]) -> [(key: ArraySlice<UInt8>, value: ArraySlice<UInt8>)] {
            guard block.count >= 4 else { return [] }
            let restarts = Int(block.suffix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) })
            let end = block.count - 4 - 4 * restarts
            guard restarts > 0, end >= 0 else { return [] }
            var out: [(ArraySlice<UInt8>, ArraySlice<UInt8>)] = []
            var i = 0, key: [UInt8] = []
            while i < end {
                guard let shared = Varint.read(block, &i), let unshared = Varint.read(block, &i),
                      let length = Varint.read(block, &i), Int(shared) <= key.count,
                      i + Int(unshared) + Int(length) <= end else { return out }
                key = Array(key.prefix(Int(shared))) + block[i..<i + Int(unshared)]
                i += Int(unshared)
                out.append((key[...], block[i..<i + Int(length)]))
                i += Int(length)
            }
            return out
        }
    }

    /// The write-ahead log: 32KB blocks of records (checksum, length, type),
    /// whose payloads join into batches of puts and deletes. Recent changes
    /// live only here until Spotify compacts them into a table.
    enum Log {
        static func entries(_ data: [UInt8], key: [UInt8]) -> [(seq: UInt64, value: [UInt8]?)] {
            var batches: [[UInt8]] = [], pending: [UInt8] = []
            var i = 0
            while i + 7 <= data.count {
                let room = 32768 - i % 32768
                if room < 7 { i += room; continue }
                let length = Int(data[i + 4]) | Int(data[i + 5]) << 8, type = data[i + 6]
                let start = i + 7
                guard length > 0 || type != 0, start + length <= data.count else { break }
                let payload = data[start..<start + length]
                switch type {
                case 1: batches.append(Array(payload))
                case 2: pending = Array(payload)
                case 3: pending += payload
                case 4: batches.append(pending + payload); pending = []
                default: break
                }
                i = start + length
            }
            var out: [(UInt64, [UInt8]?)] = []
            for batch in batches where batch.count >= 12 {
                var seq = batch.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
                var j = 12
                while j < batch.count {
                    let kind = batch[j]; j += 1
                    guard let keyLength = Varint.read(batch, &j), j + Int(keyLength) <= batch.count else { break }
                    let k = batch[j..<j + Int(keyLength)]; j += Int(keyLength)
                    var value: [UInt8]?
                    if kind == 1 {
                        guard let valueLength = Varint.read(batch, &j), j + Int(valueLength) <= batch.count else { break }
                        value = Array(batch[j..<j + Int(valueLength)]); j += Int(valueLength)
                    }
                    if Array(k) == key { out.append((seq, value)) }
                    seq += 1
                }
            }
            return out
        }
    }

    enum Varint {
        static func read<C: RandomAccessCollection>(_ bytes: C, _ i: inout C.Index) -> UInt64?
            where C.Element == UInt8 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while i < bytes.endIndex, shift < 64 {
                let byte = bytes[i]; i = bytes.index(after: i)
                result |= UInt64(byte & 0x7f) << shift
                if byte < 0x80 { return result }
                shift += 7
            }
            return nil
        }
    }

    /// Just enough protobuf to find a length-delimited field.
    enum Proto {
        static func field(_ number: UInt64, in bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8>? {
            var i = bytes.startIndex
            while i < bytes.endIndex {
                guard let tag = Varint.read(bytes, &i) else { return nil }
                switch tag & 7 {
                case 0: guard Varint.read(bytes, &i) != nil else { return nil }
                case 1: i += 8
                case 5: i += 4
                case 2:
                    guard let length = Varint.read(bytes, &i), length <= UInt64(bytes.endIndex - i) else { return nil }
                    let value = bytes[i..<i + Int(length)]
                    if tag >> 3 == number { return value }
                    i += Int(length)
                default: return nil
                }
            }
            return nil
        }
    }

    /// Snappy, decompression only: literals and back-references.
    enum Snappy {
        static func decompress(_ input: [UInt8]) -> [UInt8]? {
            var i = 0
            guard let expected = Varint.read(input, &i), expected < 64 << 20 else { return nil }
            var out: [UInt8] = []
            out.reserveCapacity(Int(expected))
            while i < input.count {
                let tag = input[i]; i += 1
                var length: Int, offset: Int
                switch tag & 3 {
                case 0:
                    length = Int(tag >> 2)
                    if length >= 60 {
                        let extra = length - 59
                        guard i + extra <= input.count else { return nil }
                        length = (0..<extra).reduce(0) { $0 | Int(input[i + $1]) << (8 * $1) }
                        i += extra
                    }
                    length += 1
                    guard i + length <= input.count else { return nil }
                    out += input[i..<i + length]; i += length
                    continue
                case 1:
                    guard i < input.count else { return nil }
                    length = Int((tag >> 2) & 7) + 4
                    offset = Int(tag >> 5) << 8 | Int(input[i]); i += 1
                case 2:
                    guard i + 2 <= input.count else { return nil }
                    length = Int(tag >> 2) + 1
                    offset = Int(input[i]) | Int(input[i + 1]) << 8; i += 2
                default:
                    guard i + 4 <= input.count else { return nil }
                    length = Int(tag >> 2) + 1
                    offset = (0..<4).reduce(0) { $0 | Int(input[i + $1]) << (8 * $1) }; i += 4
                }
                guard offset > 0, offset <= out.count else { return nil }
                for _ in 0..<length { out.append(out[out.count - offset]) }
            }
            return out.count == Int(expected) ? out : nil
        }
    }
}
