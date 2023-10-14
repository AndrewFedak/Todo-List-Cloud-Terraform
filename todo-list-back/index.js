const { default: axios } = require('axios');
const express = require('express')
const http = require('http');

const app = express();

const PORT = process.env.PORT || 80

app.get('/get-zone', async (_req, res) => {
    const req = await axios.get('http://169.254.169.254/latest/meta-data/placement/availability-zone');
    res.send(req.data)
})

app.get('/health', async (_req, res) => {
    res.send('Healthy')
})

app.listen(PORT, () => {
    console.log('successfuly listening on port: ', PORT)
})