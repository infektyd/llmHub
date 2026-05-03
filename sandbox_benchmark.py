import time

# Since Swift compiler isn't available, we will write a Python script
# to conceptualize the benchmark impact of recreating lists vs sets.
# In Python, we can benchmark the overhead.

start = time.time()
for _ in range(100000):
    lst = [".swift", ".py", ".ts", ".js", ".dart"]
    if ".png" in lst:
        pass
unoptimized_time = time.time() - start

start = time.time()
st = {".swift", ".py", ".ts", ".js", ".dart"}
for _ in range(100000):
    if ".png" in st:
        pass
optimized_time = time.time() - start

print(f"Unoptimized time (Python approximation): {unoptimized_time:.4f} s")
print(f"Optimized time (Python approximation): {optimized_time:.4f} s")
