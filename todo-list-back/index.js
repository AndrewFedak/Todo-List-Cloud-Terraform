const express = require('express')
const http = require('http');

const app = express();

const PORT = process.env.PORT || 3000

app.get('/', async (_req, res) => {
    const options = {
        hostname: '169.254.169.254',
        port: 80,
        path: '/latest/meta-data/placement/availability-zone',
        method: 'GET'
    };
    const req = http.request(options, (httpRes) => {
        let data = '';

        httpRes.on('data', (chunk) => {
            data += chunk;
        });

        httpRes.on('end', () => {
            res.send('Here is Availability Zone: ', data)
        });
    });

    req.on('error', (error) => {
        res.status(400).send('Error')
    });

    req.end();
})

app.listen(PORT, () => {
    console.log('successfuly listening')
})