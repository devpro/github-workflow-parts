// Writes the script name to report/scripts.log, so that the custom tests can check which scripts ran, and in which order.
const fs = require("node:fs");
const path = require("node:path");

// Fails when the workflow parts are in the repository, because the scripts must not read them.
if (process.env.GITHUB_WORKSPACE && fs.existsSync(path.join(process.env.GITHUB_WORKSPACE, "workflow-parts"))) {
  throw new Error("The workflow parts are beside the repository");
}
fs.mkdirSync("report", { recursive: true });
fs.appendFileSync("report/scripts.log", `${process.argv[2]}\n`);
