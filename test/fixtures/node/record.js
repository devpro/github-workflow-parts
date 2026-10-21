// Writes the name of the script run into report/scripts.log, for the custom tests of the CI to tell which ran and in which order.
const fs = require("node:fs");
const path = require("node:path");

// The scripts see the repository alone, without the workflow parts checked out beside it.
if (process.env.GITHUB_WORKSPACE && fs.existsSync(path.join(process.env.GITHUB_WORKSPACE, "workflow-parts"))) {
  throw new Error("The workflow parts are beside the repository");
}
fs.mkdirSync("report", { recursive: true });
fs.appendFileSync("report/scripts.log", `${process.argv[2]}\n`);
