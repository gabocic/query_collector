# Quer Collector

CLI tool to gather the necessary data to perform a MySQL/MariaDB slow query review.

## Requirements

* BASH 4.4.0 or above
* Perl 5
* MySQL client

## Output

```bash
userl@myhost:~/query_collector$ ./src/query_collector.sh 
============================================
===   Slow query and Stats collection    ===
============================================

2022-07-20-08:08:59 [INFO] ======= Starting collection process ========
2022-07-20-08:08:59 [INFO] mysql is present on the system
2022-07-20-08:08:59 [INFO] perl is present on the system
Please provide the Database user: collectuser
Please provide the Database password: 
If connecting through socket, please specify the path: 
Please provide the Database host [127.0.0.1]: 
Please provide the Database port [3306]: 
2022-07-20-08:09:04 [INFO] Successfully connected to database server
2022-07-20-08:09:04 [INFO] Server version is 5.7
2022-07-20-08:09:04 [WARN] Slow query log is disabled
2022-07-20-08:09:04 [INFO] Long query time set to 10.000000 seconds
2022-07-20-08:09:04 [INFO] Admin statements like ALTER TABLE or CREATE INDEX are NOT being logged
2022-07-20-08:09:04 [INFO] Slow queries executed by slave threads are not being logged
2022-07-20-08:09:04 [INFO] Minimum rows read to be included in the slow query log: 0
2022-07-20-08:09:04 [INFO] Slow query log output is set to FILE
2022-07-20-08:09:04 [INFO] Slow query log file path: /var/lib/mysql/mypc-slow.log
2022-07-20-08:09:04 [INFO] I now will aggregate slow queries and compute some stats..
2022-07-20-08:09:04 [INFO] Collecting additional schema information from the server
2022-07-20-08:09:04 [INFO] Collecting queries execution plans
2022-07-20-08:09:04 [INFO] Persistent statistics are enabled and 20 pages are sampled during calculation
2022-07-20-08:09:04 [INFO] Collecting costs information
2022-07-20-08:09:04 [INFO] Sanitizing output
2022-07-20-08:09:05 [INFO] Creating collection package
2022-07-20-08:09:05 [INFO] Collection package can be found at './src/collection_output/20220720080905_querycollector.tar.gz'
2022-07-20-08:09:05 [INFO] Collection completed successfully

```