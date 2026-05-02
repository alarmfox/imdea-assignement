P4C = p4c
P4FLAGS   = --target bmv2 --arch v1model
P4RTFLAGS = --p4runtime-files monitor.p4_16.p4info.txtpb

all: monitor.p4_16.json

monitor.p4_16.json: monitor.p4_16.p4
	$(P4C) $(P4FLAGS) $(P4RTFLAGS) $<

clean:
	rm -f monitor.p4_16.json monitor.p4_16.p4i monitor.p4_16.p4info.txtpb
