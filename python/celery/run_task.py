import time
from tasks import hello, init_celery_tracing

def main():
    init_celery_tracing()
    while True:
        result = hello()
        print(f"Task called. Result: {result}")
        time.sleep(2)

if __name__ == '__main__':
    main()
