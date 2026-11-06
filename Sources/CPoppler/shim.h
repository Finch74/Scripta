#ifndef SCRIPTA_CPOPPLER_SHIM_H
#define SCRIPTA_CPOPPLER_SHIM_H

// Poppler reads back the PDF printed by WebKitGTK so that scripta-gtk can re-draw it with cairo,
// adding page numbers and document metadata.
#include <poppler/glib/poppler.h>
#include <cairo-pdf.h>
#include <pango/pangocairo.h>

#endif
