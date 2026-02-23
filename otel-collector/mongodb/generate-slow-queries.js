// Generate slow queries to test the OTel collector's slow query extraction.
// These queries intentionally trigger COLLSCAN (no index) to exceed the 100ms threshold.

db = db.getSiblingDB("testdb");

print("Starting slow query generation...");

// 1. COLLSCAN: regex on unindexed field
print("Running regex COLLSCAN query on 'name' field...");
db.users.find({ name: { $regex: /^user_9.*/ } }).toArray();

// 2. COLLSCAN: sort on unindexed field without limit
print("Running sort COLLSCAN query on 'score' field...");
db.users.find({ status: "active" }).sort({ score: -1 }).toArray();

// 3. Aggregate pipeline with $group on unindexed field
print("Running aggregate pipeline with $group...");
db.users.aggregate([
  { $match: { "metadata.region": "us-east" } },
  {
    $group: {
      _id: "$metadata.tier",
      avgAge: { $avg: "$age" },
      avgScore: { $avg: "$score" },
      count: { $sum: 1 },
    },
  },
  { $sort: { avgScore: -1 } },
]);

// 4. COLLSCAN: $in query on unindexed 'tags' array
print("Running $in query on unindexed 'tags' array...");
db.users
  .find({ tags: { $in: ["tag_1", "tag_10", "tag_20", "tag_30", "tag_40"] } })
  .toArray();

// 5. Aggregate with $unwind + $group (expensive)
print("Running $unwind + $group aggregate...");
db.users.aggregate([
  { $unwind: "$tags" },
  { $group: { _id: "$tags", count: { $sum: 1 } } },
  { $sort: { count: -1 } },
  { $limit: 10 },
]);

print("Slow query generation complete.");
