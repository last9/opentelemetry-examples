FROM node:24.22.1-slim@sha256:1681862882da07ee5476fee047bcf34138833f1df42633bb25bcb0f438d5bf3d

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY app.js .

CMD ["node", "app.js"]
