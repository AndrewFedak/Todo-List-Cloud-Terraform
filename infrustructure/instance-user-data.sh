#!/bin/bash
# Update the package list and upgrade existing packages
sudo apt update
sudo apt upgrade -y

# Install Git
sudo apt install git -y

# Install Node.js 16.x
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/nodesource-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nodesource-archive-keyring.gpg] https://deb.nodesource.com/node_16.x $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/nodesource.list
echo "deb-src [signed-by=/usr/share/keyrings/nodesource-archive-keyring.gpg] https://deb.nodesource.com/node_16.x $(lsb_release -cs) main" | sudo tee -a /etc/apt/sources.list.d/nodesource.list
sudo apt update
sudo apt install nodejs -y

# Clone the Git repository
git clone https://github.com/AndrewFedak/todo-list-app.git

# Change directory to the todo-list-back folder
cd todo-list-back

echo "I was here"

# Install project dependencies
npm install

# Start the server (adjust this command according to your project's requirements)
npm start