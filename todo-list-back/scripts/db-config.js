const fs = require('fs')
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
const dotenv = require('dotenv')

async function getDbConfig() {
    dotenv.config({ path: './.aws.env' })

    const client = new SSMClient({
        'credentials': {
            'accessKeyId': process.env.AWS_ACCESS_KEY_ID,
            'secretAccessKey': process.env.AWS_SECRET_KEY,
        }
    });
    const [dbUsernameResponse, dbPasswordResponse, dbHostResponse] = await Promise.all([
        client.send(
            new GetParameterCommand({
                Name: "DB_USERNAME"
            })
        ),
        client.send(
            new GetParameterCommand({
                Name: "DB_PASSWORD"
            })
        ),
        client.send(
            new GetParameterCommand({
                Name: "DB_HOST"
            })
        ),
    ])
    const env = [
        `DB_USERNAME=${dbUsernameResponse.Parameter.Value}`,
        `DB_PASSWORD=${dbPasswordResponse.Parameter.Value}`,
        `DB_HOST=${dbHostResponse.Parameter.Value}`,
    ]

    fs.writeFileSync('./.db.env', env.join('\n'))
}
getDbConfig()