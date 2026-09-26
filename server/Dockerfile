FROM node:24-alpine
WORKDIR /app
RUN apk add --no-cache ffmpeg
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3003
CMD ["sh", "-c", "npm install && node --watch index.js"]
