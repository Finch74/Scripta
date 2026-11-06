import Foundation

/// Clean typographic templates used for HTML and PDF output.
///
/// All measurements are expressed in `pt` against the page content box, so the same stylesheet
/// drives the WebKit print pipeline (margins supplied by `NSPrintInfo`) and standalone HTML
/// (margins supplied by `@page` when printed from a browser, or a centred sheet on screen).
public enum ExportTemplates {
    public static func stylesheet(for mode: DocumentMode, layout: PageLayout, paper: PaperSize, forPrint: Bool) -> String {
        // WebKit prints with a minimum shrink factor of 1.25, i.e. 1 CSS px = 0.8pt instead of 0.75pt.
        // Zooming by 0.75 / 0.8 restores true physical measurements on paper.
        let page = forPrint ? """
            html { zoom: 0.9375; }
            body { padding: 0 \(layout.gutterRight)pt 0 \(layout.gutterLeft)pt; }

            """ : """
            @page { size: \(paper.cssName); margin: \(layout.top)pt \(layout.right)pt \(layout.bottom)pt \(layout.left)pt; }
            @media screen {
              html { background: #f2f2f2; }
              body { width: \(layout.contentSize.width)pt; margin: 36pt auto; padding: \(layout.top)pt \(layout.right)pt \(layout.bottom)pt \(layout.left)pt;
                     box-shadow: 0 1px 6px rgba(0,0,0,.18); }
              .page-break { border-top: 1px dashed #ccc; margin: 24pt -\(layout.left)pt 0 -\(layout.right)pt; }
            }
            @media screen and (max-width: \(Int(layout.paper.width) + 40)pt) {
              html { background: #ffffff; }
              body { width: auto; margin: 0; padding: 24pt 18pt; box-shadow: none; }
            }
            @media print {
              html, body { background: #ffffff; }
              body { width: auto; margin: 0; padding: 0; box-shadow: none; }
            }

            """
        let common = """
            *, *::before, *::after { box-sizing: border-box; }
            html, body { background: #ffffff; color: #000000; }
            ::-webkit-scrollbar { display: none; }
            body { margin: 0; -webkit-font-smoothing: antialiased; -webkit-print-color-adjust: exact; }
            .page-break { break-after: page; page-break-after: always; height: 0; }
            .note { color: #3c7f76; font-style: italic; }
            u { text-decoration-thickness: 0.5pt; text-underline-offset: 1.5pt; }

            """
        let graphicNovel = """
            .graphic-novel-tav { font-weight: bold; font-size: 1.25rem; line-height: 1.3; margin: 1.5rem 0 0.5rem;
                                 font-style: normal; text-transform: none; text-align: left;
                                 break-after: avoid; page-break-after: avoid; }
            .graphic-novel-tav:first-child, .page-break + .graphic-novel-tav { margin-top: 0; }
            .graphic-novel-tav + p { text-indent: 0; }
            .graphic-novel-panel { font-weight: bold; font-size: 1rem; line-height: 1.3; margin: 1rem 0 0.25rem;
                                   font-style: normal; text-transform: none; text-align: left;
                                   break-after: avoid; page-break-after: avoid; }
            .graphic-novel-tav + .graphic-novel-panel { margin-top: 0.5rem; }
            .graphic-novel-panel + p { text-indent: 0; }
            p.balloon { margin: 0.35rem 0 0 1.5rem; text-indent: 0; white-space: normal; }
            p.balloon + p:not(.balloon) { margin-top: 0.75rem; text-indent: 0; }


            """
        switch mode {
        case .screenplay:
            return page + common + screenplay(layout: layout) + graphicNovel
        case .prose:
            return page + common + prose + graphicNovel
        }
    }

    private static func screenplay(layout: PageLayout) -> String {
        """
        body {
          font-family: "Courier Prime", "Courier Final Draft", "Courier New", Courier, monospace;
          font-size: 12pt; line-height: 12pt;
        }
        p, h1, h2, h3 { margin: 0; font-size: 12pt; font-weight: normal; }
        .scene-heading { position: relative; margin-top: 24pt; font-weight: bold; text-transform: uppercase;
                         break-after: avoid; page-break-after: avoid; }
        .scene-heading:first-child, .page-break + .scene-heading { margin-top: 0; }
        .scene-number { position: absolute; top: 0; font-weight: normal; }
        .scene-number.left { left: -48pt; }
        .scene-number.right { right: -30pt; }
        .action { margin-top: 12pt; white-space: pre-wrap; }
        .action:first-child, .page-break + .action { margin-top: 0; }
        .dialogue-block { margin-top: 12pt; }
        .character { margin-left: 158.4pt; text-transform: uppercase; break-after: avoid; page-break-after: avoid; }
        .parenthetical { margin-left: 115.2pt; width: 158.4pt; break-after: avoid; page-break-after: avoid; }
        .dialogue { margin-left: 72pt; width: 252pt; orphans: 2; widows: 2; }
        .dual { display: flex; gap: 14.4pt; margin-top: 12pt; break-inside: avoid; page-break-inside: avoid; }
        .dual .dialogue-block { flex: 1 1 0; margin-top: 0; }
        .dual .character { margin-left: 64.8pt; }
        .dual .parenthetical { margin-left: 28.8pt; width: auto; }
        .dual .dialogue { margin-left: 0; width: auto; }
        .transition { margin-top: 12pt; text-align: right; text-transform: uppercase; }
        .centered { margin-top: 12pt; text-align: center; }
        .lyrics { margin-top: 12pt; margin-left: 72pt; font-style: italic; }
        p.note { margin-top: 12pt; }

        .title-page { height: \(layout.contentSize.height - 4)pt; display: flex; flex-direction: column;
                      break-after: page; page-break-after: always; overflow: hidden; }
        .title-page .title-block { margin-top: \(layout.contentSize.height * 0.33)pt; text-align: center; }
        .title-page .title { text-transform: uppercase; font-weight: bold; }
        .title-page .credit { margin-top: 24pt; }
        .title-page .author { margin-top: 12pt; }
        .title-page .source { margin-top: 24pt; }
        .title-page .footer { margin-top: auto; display: flex; justify-content: space-between; align-items: flex-end; gap: 36pt; }
        .title-page .contact, .title-page .meta { white-space: pre-line; }
        .title-page .meta { text-align: right; }

        """
    }

    private static let prose = """
        body {
          font-family: "Iowan Old Style", "Charter", "Georgia", "Times New Roman", serif;
          font-size: 12pt; line-height: 1.6; color: #111111;
          hyphens: auto; -webkit-hyphens: auto; overflow-wrap: break-word;
          text-rendering: optimizeLegibility; font-kerning: normal; font-variant-ligatures: common-ligatures;
        }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; color: #000000;
                                 break-after: avoid; page-break-after: avoid; hyphens: manual; -webkit-hyphens: manual; }
        h1 { font-size: 24pt; text-align: center; margin: 0 0 28pt; letter-spacing: 0.01em; }
        h2 { font-size: 16pt; margin: 28pt 0 10pt; }
        h3 { font-size: 13pt; margin: 20pt 0 6pt; }
        h4, h5, h6 { font-size: 12pt; margin: 16pt 0 4pt; font-style: italic; font-weight: 500; }
        h1 + *, h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
        p { margin: 0; orphans: 2; widows: 2; text-align: left; }
        p + p { text-indent: 1.5em; }
        blockquote { margin: 14pt 0; padding: 2pt 0 2pt 14pt; border-left: 2pt solid #d4d4d4;
                     color: #333333; font-style: italic; break-inside: avoid; page-break-inside: avoid; }
        blockquote p + p { text-indent: 0; margin-top: 6pt; }
        ul, ol { margin: 10pt 0 10pt 1.5em; padding: 0; }
        li { margin: 3pt 0; padding-left: 0.2em; }
        li > ul, li > ol { margin-top: 3pt; margin-bottom: 3pt; }
        pre { font-family: "SF Mono", Menlo, monospace; font-size: 9.5pt; line-height: 1.5; color: #1a1a1a;
              background: #f7f7f7; border: 0.5pt solid #e4e4e4; border-radius: 3pt;
              padding: 9pt 11pt; margin: 12pt 0; white-space: pre-wrap; break-inside: avoid; page-break-inside: avoid; }
        code { font-family: "SF Mono", Menlo, monospace; font-size: 0.85em; white-space: nowrap;
               background: #f3f3f3; border-radius: 2pt; padding: 0.5pt 3pt; }
        pre code { white-space: inherit; background: none; padding: 0; font-size: inherit; }
        hr { border: none; margin: 22pt 0; text-align: center; height: auto; color: #555555; }
        hr::after { content: "*  *  *"; letter-spacing: 0.5em; }
        hr + p, blockquote + p, ul + p, ol + p, pre + p, h2 + p, h3 + p { text-indent: 0; }
        a { color: inherit; text-decoration: underline; text-decoration-thickness: 0.5pt; text-underline-offset: 1.5pt; }
        img { max-width: 100%; height: auto; }

        """
}
