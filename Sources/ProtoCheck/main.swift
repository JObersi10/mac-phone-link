// Minimal entrypoint: proves the generated protobuf models link and compile
// without an Xcode/GUI toolchain. CI runs `swift build` then this binary.
import PhoneLinkProtos

print("PhoneLinkProtos OK — schema source: \(PhoneLinkProtos.schemaSourceVersion)")
