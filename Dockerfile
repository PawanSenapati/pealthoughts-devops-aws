FROM node:18.12.1
WORKDIR /app
COPY package.json /app/package.json
RUN npm install
COPY index.js /app/index.js
CMD node index.js
