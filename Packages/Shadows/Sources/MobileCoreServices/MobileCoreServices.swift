// Apple's `MobileCoreServices` module for wasm: the `kUTType` names of the common types (the
// identifiers `UTType` has, as Core Foundation strings), which image and document code still
// passes to ImageIO and the pickers. `UTType` itself is in `UniformTypeIdentifiers`.
#if os(WASI)
import WebFoundation   // `CFString`

public let kUTTypeItem: CFString = "public.item"
public let kUTTypeContent: CFString = "public.content"
public let kUTTypeData: CFString = "public.data"
public let kUTTypeText: CFString = "public.text"
public let kUTTypePlainText: CFString = "public.plain-text"
public let kUTTypeUTF8PlainText: CFString = "public.utf8-plain-text"
public let kUTTypeURL: CFString = "public.url"
public let kUTTypeFileURL: CFString = "public.file-url"
public let kUTTypeImage: CFString = "public.image"
public let kUTTypeJPEG: CFString = "public.jpeg"
public let kUTTypePNG: CFString = "public.png"
public let kUTTypeGIF: CFString = "com.compuserve.gif"
public let kUTTypeTIFF: CFString = "public.tiff"
public let kUTTypeBMP: CFString = "com.microsoft.bmp"
public let kUTTypeLivePhoto: CFString = "com.apple.live-photo"
public let kUTTypeMovie: CFString = "public.movie"
public let kUTTypeVideo: CFString = "public.video"
public let kUTTypeAudio: CFString = "public.audio"
public let kUTTypeMPEG4: CFString = "public.mpeg-4"
public let kUTTypeQuickTimeMovie: CFString = "com.apple.quicktime-movie"
public let kUTTypePDF: CFString = "com.adobe.pdf"
public let kUTTypeJSON: CFString = "public.json"
public let kUTTypeHTML: CFString = "public.html"
public let kUTTypeArchive: CFString = "public.archive"
public let kUTTypeZipArchive: CFString = "public.zip-archive"
public let kUTTypeVCard: CFString = "public.vcard"
#endif
