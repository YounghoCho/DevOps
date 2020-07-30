console.log("connection test start");

const mysql      = require('mysql');
const connection = mysql.createConnection({
//  host     : "mysql-1-mqsh6",
  host     : "10.129.0.56",
  user     : "admin",
  password : "admin",
  database : 'test'
});

connection.connect();

connection.query('SELECT * from info', (error, rows, fields) => {
  console.log('error : ' + error);
  console.log('rows : ' + JSON.stringify(rows));
  console.log('fields : ' + JSON.stringify(fields));
});

connection.end();

