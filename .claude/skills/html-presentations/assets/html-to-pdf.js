/**
 * HTML Presentation → PDF Generator (Puppeteer)
 *
 * Converts an HTML slide presentation into a high-fidelity PDF.
 * Preserves dark theme backgrounds, layouts, and visual styles.
 *
 * Usage:
 *   1. npm install puppeteer
 *   2. Edit HTML_PATH and OUTPUT_PATH below
 *   3. node html-to-pdf.js
 *
 * Key configuration:
 *   - SCALE: 0.78 default (reduce to 0.65-0.70 for very dense slides)
 *   - ICON_WAIT_MS: 2000ms default (increase if icons don't render)
 *   - PAGE_SIZE: 254mm x 142.875mm (16:9 landscape)
 */

const puppeteer = require("puppeteer");
const path = require("path");

// ============================================================
// Configuration — Edit these paths for your presentation
// ============================================================
const HTML_PATH = path.join(__dirname, "PRESENTATION_NAME.html");
const OUTPUT_PATH = path.join(__dirname, "PRESENTATION_NAME.pdf");

const SCALE = 0.78;           // Content zoom (0.65-1.0, recommended: 0.78)
const ICON_WAIT_MS = 2000;    // Wait for icon libraries (Lucide, FontAwesome) to render
const VIEWPORT_WIDTH = 1280;  // Browser viewport width
const VIEWPORT_HEIGHT = 720;  // Browser viewport height (16:9)

// ============================================================
// PDF Generation
// ============================================================
(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });

  const page = await browser.newPage();

  // Set viewport to 16:9 landscape
  await page.setViewport({ width: VIEWPORT_WIDTH, height: VIEWPORT_HEIGHT });

  // Navigate to the HTML file
  await page.goto(`file://${HTML_PATH}`, {
    waitUntil: "networkidle0",
    timeout: 30000,
  });

  // Wait for icon libraries (Lucide, FontAwesome, etc.) to render SVGs
  await new Promise((r) => setTimeout(r, ICON_WAIT_MS));

  // Use SCREEN media type to preserve dark theme visual styles
  // Without this, Puppeteer uses 'print' media which loses backgrounds
  await page.emulateMediaType("screen");

  // Inject CSS to override slide system for PDF pagination
  // Slides go from position:absolute (interactive) → position:relative (paginated)
  await page.addStyleTag({
    content: `
      @page {
        size: 254mm 142.875mm;  /* 16:9 landscape */
        margin: 0;
      }

      html, body {
        overflow: visible !important;
        height: auto !important;
        width: auto !important;
      }

      .presentation {
        position: relative !important;
        height: auto !important;
      }

      .slide {
        position: relative !important;
        opacity: 1 !important;
        visibility: visible !important;
        width: 100vw !important;
        height: 100vh !important;
        page-break-after: always !important;
        break-after: page !important;
        display: flex !important;
      }

      .slide:last-child {
        page-break-after: avoid !important;
        break-after: avoid !important;
      }

      /* Hide navigation elements */
      .nav-controls,
      .progress-bar,
      .brand-footer {
        display: none !important;
      }

      /* Ensure backgrounds are printed */
      * {
        -webkit-print-color-adjust: exact !important;
        print-color-adjust: exact !important;
        color-adjust: exact !important;
      }
    `,
  });

  // Generate PDF
  await page.pdf({
    path: OUTPUT_PATH,
    printBackground: true,        // ESSENTIAL for dark theme
    preferCSSPageSize: true,      // Use @page size (254mm x 142.875mm)
    landscape: true,              // Landscape orientation
    scale: SCALE,                 // Content zoom (0.78 avoids overflow)
    margin: { top: "0", right: "0", bottom: "0", left: "0" },
    timeout: 60000,
  });

  await browser.close();
  console.log(`PDF generated: ${OUTPUT_PATH}`);
})();
