# query-optimization.com python module
This simple module allows you to submit query optimization jobs automatically, by just specifying the connection parameters and the query to optimize. The account used for collection should have enough privileges to execute the query, although running it is not needed for the analysis.

## Python modules required

 1. mysqlclient
 2. requests
 3. sqlglot
 4. sqlparse


## Example 

    # Import optimization job object
    from collector import OptJob
    
    # Import json for pretty printing
    import json
    
    # Query to analyze
    sqltext = "SELECT DISTINCT     f.flightno,     ap1.name AS from_ap,     ap2.name AS dest_ap,     apg.name AS emergency_ap,     ST_DISTANCE(ap1.geolocation, ap2.geolocation) AS distance,     ST_DISTANCE(ap1.geolocation, apg.geolocation) AS emergency_distance FROM     flight f         JOIN     (SELECT         airport_id, name, geolocation     FROM         airport_geo     WHERE         country IN ('MEXICO' , 'CANADA')) ap1 ON (f.from = ap1.airport_id)         JOIN     (SELECT         airport_id, name, geolocation     FROM         airport_geo     WHERE         country = 'UNITED STATES') ap2 ON (f.to = ap2.airport_id)         JOIN     airport_geo apg ON (ST_DISTANCE(ap1.geolocation, apg.geolocation) < 5) WHERE     apg.country IN ('CANADA' , 'MEXICO', 'UNITED STATES')"
    
    # Instantiate optimization job by passing connections parameters, together with the query
    myjob = OptJob('127.0.0.1','myuser','secretpass','mydb',3306,sqltext)
	
	# Run analysis
	myjob.analyze()
	
	# Print job_id and analysis results
	print(json.dumps(myjob.analysis_result,indent=4))
	
	# Delete object
	del myjob
