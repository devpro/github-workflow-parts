// Writes the site the Pages deployment workflow checks, as a site generator would.
const fs = require("node:fs");
fs.mkdirSync("_site", { recursive: true });
fs.writeFileSync("_site/index.html", "<!doctype html><title>Fixture</title>\n");
