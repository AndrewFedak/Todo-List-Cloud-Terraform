const fs = require('fs')
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
// const { fromIni } = require("@aws-sdk/credential-providers");

async function getDbConfig() {
    // Profile config taken from:  ~/.aws/config
    // Profile credentials taken from:  ~/.aws/credentials
    const client = new SSMClient();

    const [dbUsernameResponse, dbPasswordResponse, dbHostResponse] = await Promise.all([
        client.send(
            new GetParameterCommand({
                Name: "DB_USERNAME",
            })
        ),
        client.send(
            new GetParameterCommand({
                Name: "DB_PASSWORD"
            })
        ),
        client.send(
            new GetParameterCommand({
                Name: "DB_HOST",
                'WithDecryption': true
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