module json2

const concurrent_cache_workers = 64
const concurrent_cache_iterations = 32

struct ConcurrentEncodeFixture {
	id       int
	name     string
	enabled  bool
	quantity f64
	region   string @[json: 'execution_region']
	secret   string @[skip]
}

struct ConcurrentDecodeFixture {
	id       int
	name     string
	enabled  bool
	quantity f64
	region   string @[json: 'execution_region']
	secret   string @[skip]
}

struct ConcurrentEncodeFixtureB {
	symbol  string
	risk    int @[json: 'risk_units']
	active  bool
	ignored string @[json: '-']
}

struct ConcurrentDecodeFixtureB {
	symbol  string
	risk    int @[json: 'risk_units']
	active  bool
	ignored string @[json: '-']
}

fn concurrent_encode_worker(ready chan bool, start chan bool, done chan string) {
	ready <- true
	_ := <-start
	for _ in 0 .. concurrent_cache_iterations {
		encoded := encode(ConcurrentEncodeFixture{
			id:       7
			name:     'lease-a'
			enabled:  true
			quantity: 1.25
			region:   'ldn'
			secret:   'not-serialized'
		})
		if encoded != '{"id":7,"name":"lease-a","enabled":true,"quantity":1.25,"execution_region":"ldn"}' {
			done <- 'error'
			return
		}
	}
	done <- 'a'
}

fn concurrent_encode_worker_b(ready chan bool, start chan bool, done chan string) {
	ready <- true
	_ := <-start
	for _ in 0 .. concurrent_cache_iterations {
		encoded := encode(ConcurrentEncodeFixtureB{
			symbol:  'XAUUSD'
			risk:    3
			active:  true
			ignored: 'not-serialized'
		})
		if encoded != '{"symbol":"XAUUSD","risk_units":3,"active":true}' {
			done <- 'error'
			return
		}
	}
	done <- 'b'
}

fn concurrent_decode_worker(ready chan bool, start chan bool, done chan int) {
	ready <- true
	_ := <-start
	for _ in 0 .. concurrent_cache_iterations {
		value := decode[ConcurrentDecodeFixture]('{"id":7,"name":"lease-a","enabled":true,"quantity":1.25,"execution_region":"ldn","secret":"ignored"}') or {
			done <- -1
			return
		}
		if value.id != 7 || value.name != 'lease-a' || !value.enabled || value.quantity != 1.25
			|| value.region != 'ldn' || value.secret != '' {
			done <- -1
			return
		}
	}
	done <- 7
}

fn concurrent_decode_worker_b(ready chan bool, start chan bool, done chan int) {
	ready <- true
	_ := <-start
	for _ in 0 .. concurrent_cache_iterations {
		value := decode[ConcurrentDecodeFixtureB]('{"symbol":"XAUUSD","risk_units":3,"active":true,"ignored":"skip-me"}') or {
			done <- -1
			return
		}
		if value.symbol != 'XAUUSD' || value.risk != 3 || !value.active || value.ignored != '' {
			done <- -1
			return
		}
	}
	done <- 11
}

fn test_concurrent_first_encode_initializes_field_cache_once() {
	ready := chan bool{cap: concurrent_cache_workers}
	start := chan bool{cap: concurrent_cache_workers}
	done := chan string{cap: concurrent_cache_workers}
	for _ in 0 .. concurrent_cache_workers / 2 {
		spawn concurrent_encode_worker(ready, start, done)
		spawn concurrent_encode_worker_b(ready, start, done)
	}
	for _ in 0 .. concurrent_cache_workers {
		_ = <-ready
	}
	for _ in 0 .. concurrent_cache_workers {
		start <- true
	}
	mut count_a := 0
	mut count_b := 0
	for _ in 0 .. concurrent_cache_workers {
		match <-done {
			'a' { count_a++ }
			'b' { count_b++ }
			else { assert false }
		}
	}
	assert count_a == concurrent_cache_workers / 2
	assert count_b == concurrent_cache_workers / 2
}

fn test_concurrent_first_decode_initializes_field_cache_once() {
	ready := chan bool{cap: concurrent_cache_workers}
	start := chan bool{cap: concurrent_cache_workers}
	done := chan int{cap: concurrent_cache_workers}
	for _ in 0 .. concurrent_cache_workers / 2 {
		spawn concurrent_decode_worker(ready, start, done)
		spawn concurrent_decode_worker_b(ready, start, done)
	}
	for _ in 0 .. concurrent_cache_workers {
		_ = <-ready
	}
	for _ in 0 .. concurrent_cache_workers {
		start <- true
	}
	mut count_a := 0
	mut count_b := 0
	for _ in 0 .. concurrent_cache_workers {
		match <-done {
			7 { count_a++ }
			11 { count_b++ }
			else { assert false }
		}
	}
	assert count_a == concurrent_cache_workers / 2
	assert count_b == concurrent_cache_workers / 2
}
