#pragma once

// Match the desktop's artwork priority. A copy of the Mac selection can be
// updated in Documents independently of the game binary and its writable data.
static UIImage *TTLibraryArtworkInDirectory(NSString *directory, NSString *stem) {
    for (NSString *ext in @[@"jpg", @"png", @"jpeg", @"heic", @"webp"]) {
        UIImage *image = [UIImage imageWithContentsOfFile:[directory stringByAppendingPathComponent:[stem stringByAppendingPathExtension:ext]]];
        if (image) return image;
    }
    return nil;
}

static UIImage *TTLibraryPreferredArtwork(NSString *titleID, BOOL hero) {
    if (!titleID.length || ![titleID isEqualToString:titleID.lastPathComponent] ||
        [titleID isEqualToString:@"."] || [titleID isEqualToString:@".."]) return nil;
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *art = [[doc stringByAppendingPathComponent:@"LibraryArtwork"] stringByAppendingPathComponent:titleID.lowercaseString];
    NSString *framework = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:
        [NSString stringWithFormat:@"DmGame%@.framework", titleID.uppercaseString]];
    if (!hero) {
        UIImage *image = TTLibraryArtworkInDirectory(art, @"thumbnail");
        if (image) return image;
    }
    return TTLibraryArtworkInDirectory(art, @"hero") ?: TTLibraryArtworkInDirectory(art, @"banner") ?:
           TTLibraryArtworkInDirectory(framework, @"banner");
}
