// Generate slow queries against a MongoDB Atlas cluster to test OTel slow query extraction.
// Usage: mongosh "mongodb+srv://user:pass@cluster.mongodb.net/testdb" generate-slow-queries.js

db = db.getSiblingDB("testdb");

// Seed data if not already present
var count = db.users.countDocuments();
if (count < 50000) {
  print("Seeding 50000 documents into testdb.users...");
  var batchSize = 5000;
  for (var batch = 0; batch < 50000 / batchSize; batch++) {
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
        },
        description:
          "This is a longer text field for user " +
          idx +
          " to increase document size and slow down collection scans.",
        createdAt: new Date(),
      });
    }
    bulk.execute();
  }
  print("Seeding complete. Total docs: " + db.users.countDocuments());
} else {
  print("testdb.users already has " + count + " documents, skipping seed.");
}

// Drop any secondary indexes to force COLLSCAN
var indexes = db.users.getIndexes();
indexes.forEach(function (idx) {
  if (idx.name !== "_id_") {
    print("Dropping index: " + idx.name);
    db.users.dropIndex(idx.name);
  }
});

print("\nStarting slow query generation...");

// 1. Regex COLLSCAN on unindexed field
print("Running regex COLLSCAN on 'description'...");
start = new Date();
db.users
  .find({ description: { $regex: /.*user_999[0-9].*increase.*slow/ } })
  .toArray();
print("Regex COLLSCAN took: " + (new Date() - start) + "ms");

// 3. Sort on unindexed field
print("Running sort COLLSCAN on 'score'...");
start = new Date();
db.users.find({}).sort({ score: 1, age: -1 }).limit(10000).toArray();
print("Sort COLLSCAN took: " + (new Date() - start) + "ms");

// 4. Aggregate with $unwind + $group (expensive)
print("Running $unwind + $group aggregate...");
start = new Date();
db.users.aggregate([
  { $unwind: "$tags" },
  { $group: { _id: "$tags", count: { $sum: 1 } } },
  { $sort: { count: -1 } },
  { $limit: 10 },
]);
print("$unwind + $group took: " + (new Date() - start) + "ms");

// 5. $in query on unindexed array
print("Running $in query on unindexed 'tags'...");
start = new Date();
db.users
  .find({
    tags: { $in: ["tag_1", "tag_10", "tag_20", "tag_30", "tag_40", "tag_49"] },
  })
  .toArray();
print("$in query took: " + (new Date() - start) + "ms");

// 6. Multiple rounds to increase chance of exceeding Atlas slow query threshold
print("Running 3 additional rounds of heavy queries...");
for (var round = 0; round < 3; round++) {
  print("  Round " + (round + 1) + "...");
  db.users.find({ description: { $regex: /.*user_[0-9]{4}.*increase/ } }).toArray();
  db.users.find({}).sort({ score: 1, age: -1, name: 1 }).limit(50000).toArray();
  db.users.aggregate([
    { $unwind: "$tags" },
    { $group: { _id: { tag: "$tags", region: "$metadata.region" }, count: { $sum: 1 }, avgScore: { $avg: "$score" } } },
    { $sort: { count: -1 } },
  ]);
}

print("\nSlow query generation complete.");
print(
  "Note: Atlas logs slow queries asynchronously. Wait 3-5 minutes for them to appear in the collector."
);
