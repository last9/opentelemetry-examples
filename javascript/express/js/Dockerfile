# Use Node.js 14 as the base image
FROM node:14

# Set the working directory
WORKDIR /usr/src/app

# Copy package.json and package-lock.json
COPY package.json package-lock.json ./

# Install dependencies
RUN npm install

# Copy the rest of the application code
COPY . .

# Expose the port the app runs on (default: 3000)
EXPOSE 3000

# Start the server
CMD ["npm", "start"] 