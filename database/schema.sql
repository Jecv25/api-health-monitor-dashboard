-- Generated from SQLAlchemy models; MySQL 8.4. UTC DATETIME values.



CREATE TABLE endpoints (
	id INTEGER NOT NULL AUTO_INCREMENT, 
	name VARCHAR(80) NOT NULL, 
	url VARCHAR(512) NOT NULL, 
	owner_group VARCHAR(40) NOT NULL, 
	interval_seconds INTEGER NOT NULL, 
	timeout_seconds INTEGER NOT NULL, 
	enabled BOOL NOT NULL, 
	status VARCHAR(20) NOT NULL, 
	recovery_streak INTEGER NOT NULL, 
	created_at DATETIME(6) NOT NULL, 
	last_check_at DATETIME(6), 
	next_check_at DATETIME(6) NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (url)
)

;

CREATE INDEX ix_endpoints_next_check_at ON endpoints (next_check_at);


CREATE TABLE worker_heartbeats (
	name VARCHAR(24) NOT NULL, 
	updated_at DATETIME(6) NOT NULL, 
	PRIMARY KEY (name)
)

;


CREATE TABLE check_runs (
	id VARCHAR(36) NOT NULL, 
	endpoint_id INTEGER NOT NULL, 
	idempotency_key VARCHAR(64) NOT NULL, 
	correlation_id VARCHAR(36) NOT NULL, 
	source VARCHAR(16) NOT NULL, 
	status VARCHAR(24) NOT NULL, 
	success BOOL, 
	http_status INTEGER, 
	duration_ms FLOAT, 
	error_code VARCHAR(40), 
	started_at DATETIME(6) NOT NULL, 
	finished_at DATETIME(6), 
	PRIMARY KEY (id), 
	CONSTRAINT uq_run_submission UNIQUE (endpoint_id, idempotency_key), 
	FOREIGN KEY(endpoint_id) REFERENCES endpoints (id)
)

;

CREATE INDEX ix_runs_endpoint_started ON check_runs (endpoint_id, started_at);

CREATE INDEX ix_check_runs_started_at ON check_runs (started_at);


CREATE TABLE check_attempts (
	id INTEGER NOT NULL AUTO_INCREMENT, 
	run_id VARCHAR(36) NOT NULL, 
	number INTEGER NOT NULL, 
	success BOOL NOT NULL, 
	http_status INTEGER, 
	duration_ms FLOAT NOT NULL, 
	error_code VARCHAR(40), 
	recorded_at DATETIME(6) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_attempt_number UNIQUE (run_id, number), 
	FOREIGN KEY(run_id) REFERENCES check_runs (id)
)

;


CREATE TABLE incidents (
	id INTEGER NOT NULL AUTO_INCREMENT, 
	endpoint_id INTEGER NOT NULL, 
	status VARCHAR(20) NOT NULL, 
	owner_group VARCHAR(40) NOT NULL, 
	opened_at DATETIME(6) NOT NULL, 
	acknowledged_at DATETIME(6), 
	acknowledged_by VARCHAR(40), 
	note VARCHAR(240), 
	recovered_at DATETIME(6), 
	opening_run_id VARCHAR(36) NOT NULL, 
	recovery_run_id VARCHAR(36), 
	PRIMARY KEY (id), 
	FOREIGN KEY(endpoint_id) REFERENCES endpoints (id), 
	FOREIGN KEY(opening_run_id) REFERENCES check_runs (id), 
	FOREIGN KEY(recovery_run_id) REFERENCES check_runs (id)
)

;

CREATE INDEX ix_incidents_endpoint_id ON incidents (endpoint_id);


CREATE TABLE notifications (
	id INTEGER NOT NULL AUTO_INCREMENT, 
	endpoint_id INTEGER NOT NULL, 
	incident_id INTEGER NOT NULL, 
	kind VARCHAR(24) NOT NULL, 
	message VARCHAR(240) NOT NULL, 
	created_at DATETIME(6) NOT NULL, 
	read_at DATETIME(6), 
	PRIMARY KEY (id), 
	FOREIGN KEY(endpoint_id) REFERENCES endpoints (id), 
	FOREIGN KEY(incident_id) REFERENCES incidents (id)
)

;