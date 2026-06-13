const { fishing } = require("./fishing");
const { starGazing } = require("./starGazing");
const { volleyBall } = require("./volleyBall");

const activities = [...fishing, ...volleyBall, ...starGazing];

module.exports = { activities };
