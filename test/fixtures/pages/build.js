// Writes a site in the same way as a site generator, to test the Pages deployment workflow.
const fs = require("node:fs");
fs.mkdirSync("_site", { recursive: true });
fs.writeFileSync("_site/index.html", "<!doctype html><title>Fixture</title>\n");
