import { NextApiRequest } from "next";

export const GET = async (req: NextApiRequest) => {
  return Response.json({ message: "Hello World" });
};

export const PUT = async (req: NextApiRequest) => {
  return Response.json({ message: "Hello World" });
};

export const DELETE = async (req: NextApiRequest) => {
  return Response.json({ message: "Hello World" });
};
