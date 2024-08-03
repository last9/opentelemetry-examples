import { NextApiRequest } from "next";

export const GET = async (req: NextApiRequest) => {
  return Response.json({ message: "Hello World" });
};

export const POST = async (req: NextApiRequest) => {
  return Response.json({ message: "Hello World" });
};
