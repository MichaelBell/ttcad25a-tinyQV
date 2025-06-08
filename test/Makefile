.PHONY: all

%-results.xml:
	make -f test_$*.mk clean
	make -f test_$*.mk
	mv results.xml $@

peri-%.xml:
	make -f test_basic.mk clean
	MODULE=user_peripherals.$* make -f test_basic.mk
	mv results.xml $@

all: clean peri-edge_counter.xml peri-simple_pwm.xml peri-game_pmod.xml basic-results.xml prog-results.xml
	cat *results.xml peri-*.xml > results.xml

clean:
	rm *results.xml peri-*.xml || true