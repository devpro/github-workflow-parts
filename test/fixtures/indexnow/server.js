// Serves a sitemap index of two sitemaps, and an IndexNow API that records what it is sent, for the IndexNow action to be tested without reaching IndexNow.
// Usage: node server.js <file the submission is written to> <port>
const fs = require("node:fs");
const http = require("node:http");

const [recordPath, port] = process.argv.slice(2);
const origin = `http://127.0.0.1:${port}`;
const urlset = (...locs) =>
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${locs.map((loc) => `  <url>\n    <loc>\n      ${loc}\n    </loc>\n  </url>`).join("\n")}\n</urlset>\n`;
const pages = {
  "/sitemap.xml": `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n  <sitemap><loc>${origin}/pages.xml</loc></sitemap>\n  <sitemap><loc>${origin}/posts.xml</loc></sitemap>\n</sitemapindex>\n`,
  "/pages.xml": urlset(`${origin}/a?x=1&amp;y=2`, `${origin}/b`),
  "/posts.xml": urlset(`${origin}/c`),
};

http
  .createServer((req, res) => {
    if (req.method === "GET" && pages[req.url]) {
      res.writeHead(200, { "content-type": "application/xml" }).end(pages[req.url]);
      return;
    }
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      if (req.method === "POST" && req.url === "/indexnow") {
        fs.writeFileSync(recordPath, body);
        res.writeHead(202).end();
      } else if (req.method === "POST" && req.url === "/refuse") {
        res.writeHead(422).end("Unprocessable Entity: the URLs do not belong to the host, or the key does not match the schema");
      } else {
        res.writeHead(404).end();
      }
    });
  })
  .listen(Number(port), "127.0.0.1");
