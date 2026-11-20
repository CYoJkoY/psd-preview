const std = @import("std");

pub const windows = std.os.windows;

/// Human-readable registry identities. The GUID values below are parsed from
/// these strings so the COM constants and the registry layout cannot drift.
pub const clsid_text = "{7B9E4A10-3C82-4F51-9D2A-8E1C6B04F291}";
pub const appid_text = "{6D2B5079-2F0B-48DD-AB7F-97CEC514D30B}";
pub const thumbnail_iid_text = "{E357FCCD-A995-4576-B01F-234630154E96}";
pub const preview_iid_text = "{8895B1C6-B41F-4C1C-A562-0D564250836F}";
pub const handler_name = "Zig PSD/PSB Thumbnail & Preview Handler";
pub const preview_handler_name = "Zig PSD/PSB Preview Handler";
pub const supported_extensions = [_][]const u8{ ".psd", ".psb" };

pub const extension_clsid = windows.GUID.parse(clsid_text);
pub const appid = windows.GUID.parse(appid_text);
pub const thumbnail_iid = windows.GUID.parse(thumbnail_iid_text);
pub const preview_iid = windows.GUID.parse(preview_iid_text);
pub const initialize_stream_iid = windows.GUID.parse("{B824B49D-22AC-4161-AC8A-9916E8FA3F7F}");
pub const ole_window_iid = windows.GUID.parse("{00000114-0000-0000-C000-000000000046}");
pub const object_with_site_iid = windows.GUID.parse("{FC4801A3-2BA9-11CF-A229-00AA003D7352}");
pub const class_factory_iid = windows.GUID.parse("{00000001-0000-0000-C000-000000000046}");
pub const unknown_iid = windows.GUID.parse("{00000000-0000-0000-C000-000000000046}");

pub const max_decode_bytes: usize = 256 * 1024 * 1024;
/// Keeps dimensions within the range the PSD decoders and GDI paths can
/// represent without relying on saturating casts.
pub const max_image_dimension: u32 = 100000;
/// Explorer asks for thumbnail sizes in logical pixels; larger requests are
/// clamped so a hostile host cannot force an unbounded allocation.
pub const max_thumbnail_dimension: u32 = 1024;
/// Combined working memory for decoded planes plus premultiplied BGRA output.
pub const max_working_bytes: usize = 256 * 1024 * 1024;
pub const min_zoom: f32 = 0.1;
pub const max_zoom: f32 = 16.0;
