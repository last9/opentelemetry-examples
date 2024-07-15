import { IUser } from "@src/models/User";

// **** Types **** //

interface IDb {
  users: IUser[];
}

let dbFile = {
  users: [
    {
      id: 366115170645,
      name: "Sean Maxwell",
      email: "smaxwell@example.com",
      created: new Date("2024-03-22T05:14:36.252Z"),
    },
    {
      id: 310946254456,
      name: "John Smith",
      email: "john.smith@example.com",
      created: new Date("2024-03-22T05:20:55.079Z"),
    },
    {
      id: 143027113460,
      name: "Gordan Freeman",
      email: "nova@prospect.com",
      created: new Date("2024-03-22T05:42:18.895Z"),
    },
  ],
};

// **** Functions **** //

/**
 * Fetch the json from the file.
 */
function openDb(): Promise<IDb> {
  return new Promise((resolve, reject) => {
    resolve(dbFile);
  });
}

/**
 * Update the file.
 */
function saveDb(db: IDb): Promise<void> {
  return new Promise((resolve, reject) => {
    dbFile = db;
    resolve();
  });
}

// **** Export default **** //

export default {
  openDb,
  saveDb,
} as const;
