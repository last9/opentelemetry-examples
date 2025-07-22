import time
import os

def continuous_log_writer():
    os.makedirs('/log', exist_ok=True)
    with open('/log/app.log', 'a') as f:
        while True:
            f.write(f"Log entry at {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.flush()
            time.sleep(1)

if __name__ == "__main__":
    continuous_log_writer() 