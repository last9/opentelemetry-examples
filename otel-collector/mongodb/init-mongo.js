// Create monitoring role and user for OpenTelemetry Collector
// Runs automatically on first container startup via /docker-entrypoint-initdb.d/

db = db.getSiblingDB("admin");

// Custom role for index access metrics (mongodb.index.access.count)
db.createRole({
  role: "indexStatsRole",
  privileges: [
    {
      resource: { db: "admin", collection: "system.profile" },
      actions: ["indexStats", "find"],
    },
    {
      resource: { db: "config", collection: "system.profile" },
      actions: ["indexStats", "find"],
    },
    {
      resource: { db: "local", collection: "system.profile" },
      actions: ["indexStats", "find"],
    },
    {
      resource: { db: "", collection: "system.profile" },
      actions: ["indexStats", "find"],
    },
  ],
  roles: [],
});

// Create monitoring user with least-privilege roles
db.createUser({
  user: "otel",
  pwd: "otel_password",
  roles: [
    { role: "clusterMonitor", db: "admin" },
    { role: "read", db: "local" },
    { role: "indexStatsRole", db: "admin" },
  ],
  mechanisms: ["SCRAM-SHA-1", "SCRAM-SHA-256"],
});

// Seed test data for slow query generation
db = db.getSiblingDB("testdb");

// Create a collection with sample documents (no secondary indexes)
// 100K docs ensures COLLSCAN queries exceed the 100ms slowOpThreshold
var batchSize = 5000;
var totalDocs = 100000;
for (var batch = 0; batch < totalDocs / batchSize; batch++) {
  var bulk = db.users.initializeUnorderedBulkOp();
  for (var i = 0; i < batchSize; i++) {
    var idx = batch * batchSize + i;
    bulk.insert({
      name: "user_" + idx,
      email: "user_" + idx + "@example.com",
      age: Math.floor(Math.random() * 80) + 18,
      score: Math.random() * 100,
      status: ["active", "inactive", "pending"][Math.floor(Math.random() * 3)],
      tags: [
        "tag_" + Math.floor(Math.random() * 50),
        "tag_" + Math.floor(Math.random() * 50),
        "tag_" + Math.floor(Math.random() * 50),
      ],
      metadata: {
        region: ["us-east", "us-west", "eu-west", "ap-south"][
          Math.floor(Math.random() * 4)
        ],
        tier: ["free", "basic", "premium"][Math.floor(Math.random() * 3)],
        signupDate: new Date(
          Date.now() - Math.floor(Math.random() * 365 * 24 * 60 * 60 * 1000)
        ),
      },
      description: "This is a longer text field for user " + idx + " to increase document size and slow down collection scans during query execution without indexes.",
      createdAt: new Date(),
    });
  }
  bulk.execute();
}

print("Inserted " + totalDocs + " test documents into testdb.users");

// Grant read access to otel user on testdb for index stats
db = db.getSiblingDB("admin");
db.grantRolesToUser("otel", [{ role: "read", db: "testdb" }]);
