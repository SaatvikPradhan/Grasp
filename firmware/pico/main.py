# Grasp bench on a Raspberry Pi Pico W (MicroPython): two thermistor cups, room air, buzzer, LCD.
# Simple version.
# Same serial messages as grasp_bath.ino, so the Mac app doesn't change.
#
# Wiring (3V3 = pin 36 -> red rail, GND = pin 38 -> blue rail)
#   Thermistor A : 3V3 -- thermistor -- GP26 (pin 31) -- 10k -- GND
#   Thermistor B : 3V3 -- thermistor -- GP27 (pin 32) -- 10k -- GND
#   DHT11 module : S -> GP13 (pin 17), + -> 3V3, - -> GND   (room air, optional)
#   Buzzer       : + -> 3V3, - -> S8050 C; S8050 E -> GND; S8050 B -> 1k -> GP15 (pin 20)
#   I2C LCD 1602 : SDA -> GP4 (pin 6), SCL -> GP5 (pin 7), VCC -> VBUS (pin 40), GND -> GND
#
# Board -> Mac (once a second):  READY | T,A,44.21 | T,B,39.87 | T,R,23.00 | ALERT,B | CAL,<offA>,<offB>
# Mac -> Board:  CAL | TARGET,<c> | BEEP | LCD,<text> | LCD   (and PING -> PONG)
import math
import select
import sys
import time
from machine import ADC, I2C, Pin

PIN_A, PIN_B = 26, 27        # thermistor junctions (ADC0, ADC1)
PIN_DHT = 13                 # set to None if there's no DHT11
PIN_BUZZ = 15                # S8050 base, through 1 k
R_FIXED, R0, BETA, T0 = 10000.0, 10000.0, 3950.0, 298.15

target = 37.0
off = {'A': 0.0, 'B': 0.0}   # set by CAL
temps = {'A': None, 'B': None}
above = {'A': False, 'B': False}
room = None
line2 = ''


def read_thermistor(adc):
    raw = sum(adc.read_u16() for _ in range(32)) / 32
    if raw < 300 or raw > 65200:
        return None                       # unplugged, or a wet (shorted) joint
    r = R_FIXED * (65535 / raw - 1)       # thermistor on top, 10 k to GND
    return 1 / (1 / T0 + math.log(r / R0) / BETA) - 273.15


buzzer = Pin(PIN_BUZZ, Pin.OUT, value=0)


def beep(n):
    for _ in range(n):
        buzzer.value(1); time.sleep_ms(120)
        buzzer.value(0); time.sleep_ms(100)


class Lcd:
    '''HD44780 1602 behind a PCF8574 I2C backpack.'''

    def __init__(self):
        self.i2c = I2C(0, sda=Pin(4), scl=Pin(5), freq=100000)
        found = self.i2c.scan()
        self.addr = 0x27 if 0x27 in found else (found[0] if found else 0x27)
        for c in (0x33, 0x32, 0x28, 0x0C, 0x06, 0x01):
            self.cmd(c)

    def nibble(self, bits, data):
        b = (bits & 0xF0) | (0x01 if data else 0) | 0x08     # 0x08 = backlight on
        self.i2c.writeto(self.addr, bytes([b | 0x04, b]))

    def byte(self, v, data):
        self.nibble(v, data); self.nibble(v << 4, data)

    def cmd(self, v):
        self.byte(v, False); time.sleep_ms(2)

    def show(self, row, text):
        self.cmd(0x80 | (0x40 if row else 0))
        for ch in (text + ' ' * 16)[:16]:
            self.byte(ord(ch), True)


def fmt(cup):
    t = temps[cup]
    return cup + (' --.-' if t is None else '%.1f' % t)


def handle(cmd):
    global target, line2
    cmd = cmd.strip()
    if cmd == 'CAL':                      # put BOTH probes in the same cup first
        a, b = temps['A'], temps['B']
        if a is not None and b is not None:
            a -= off['A']; b -= off['B']  # back to raw readings
            m = (a + b) / 2
            off['A'], off['B'] = m - a, m - b
        print('CAL,%.2f,%.2f' % (off['A'], off['B']))
    elif cmd.startswith('TARGET,'):
        try:
            target = float(cmd[7:])
        except ValueError:
            pass
    elif cmd == 'BEEP':
        beep(1)
    elif cmd.startswith('LCD,'):
        line2 = cmd[4:]
    elif cmd == 'LCD':
        line2 = ''
    elif cmd == 'PING':
        print('PONG')


def check_alert(cup):
    t = temps[cup]
    if t is None:
        return
    if above[cup] and t < target:
        above[cup] = False
        print('ALERT,' + cup)
        beep(3)
    elif not above[cup] and t > target + 0.2:
        above[cup] = True


def main():
    global room
    adc = {'A': ADC(PIN_A), 'B': ADC(PIN_B)}
    room_sensor = None
    if PIN_DHT is not None:
        import dht
        room_sensor = dht.DHT11(Pin(PIN_DHT))
    try:
        lcd = Lcd()
        lcd.show(0, 'Grasp  37.0 C'); lcd.show(1, 'ready')
    except Exception:
        lcd = None                        # runs fine without the screen

    poll = select.poll()
    poll.register(sys.stdin, select.POLLIN)
    buf = ''
    print('READY')
    last_read = last_dht = time.ticks_ms()

    while True:
        while poll.poll(0):               # commands from the Mac, whole lines only
            ch = sys.stdin.read(1)
            if ch in '\r\n':
                if buf:
                    handle(buf)
                buf = ''
            else:
                buf = (buf + ch)[-80:]

        now = time.ticks_ms()
        if room_sensor and time.ticks_diff(now, last_dht) >= 2000:   # DHT11 is slow
            last_dht = now
            try:
                room_sensor.measure()
                room = room_sensor.temperature()
            except Exception:
                pass

        if time.ticks_diff(now, last_read) >= 1000:
            last_read = time.ticks_add(last_read, 1000)
            for cup in 'AB':
                t = read_thermistor(adc[cup])
                temps[cup] = None if t is None else t + off[cup]
                if temps[cup] is not None:
                    print('T,%s,%.2f' % (cup, temps[cup]))
            if room is not None:
                print('T,R,%.2f' % room)
            check_alert('A')
            check_alert('B')
            if lcd:
                lcd.show(0, fmt('A') + '  ' + fmt('B'))
                if line2:
                    lcd.show(1, line2)
                elif temps['B'] is not None and temps['B'] < target and not above['B']:
                    lcd.show(1, 'B below %.0f C!' % target)
                elif room is not None:
                    lcd.show(1, 'Room %.0f C' % room)
                else:
                    lcd.show(1, '')
        time.sleep_ms(5)


main()
