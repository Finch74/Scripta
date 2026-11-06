#ifndef SCRIPTA_CWEBKIT_SHIM_H
#define SCRIPTA_CWEBKIT_SHIM_H

// WebKitGTK 6.0 (the GTK 4 build of WebKit), used by scripta-gtk to lay out and paginate PDF exports.
#define GDK_DISABLE_DEPRECATION_WARNINGS
#include <webkit/webkit.h>

#endif
