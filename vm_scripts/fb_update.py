import requests, json

API = 'http://localhost:8000'
r = requests.post(f'{API}/api/v1/applications/token', json={
    'client_id': 'a1e7af3c-c216-42ef-b5e6-0484eaafae56',
    'client_secret': 'u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc'
})
token = r.json()['access_token']
headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

# List ALL recent jobs across all connections
for conn_name, conn_id in [
    ('Facebook', '5558bb48-a4ec-49ba-9e48-b9ca92f3461f'),
    ('TikTok', '292df228-3e1b-4dc2-879e-bd78cc15bcf8'),
    ('Shopify', 'c79a5968-f31b-44b9-b9e6-fa79e630fa40'),
]:
    jobs_r = requests.post(f'{API}/api/v1/jobs/list', headers=headers, json={
        'configId': conn_id, 'configTypes': ['sync']
    })
    jobs = jobs_r.json().get('jobs', [])[:2]
    for j in jobs:
        job = j.get('job', {})
        attempts = j.get('attempts', [])
        last = attempts[-1].get('attempt', {}) if attempts else {}
        stats = last.get('totalStats', {})
        rec = stats.get('recordsEmitted', 0)
        committed = stats.get('recordsCommitted', 0)
        stream_stats = last.get('streamStats', [])
        stream_count = len(stream_stats)
        print(f"[{conn_name}] Job {job.get('id')}: {job.get('status')} | emit={rec:,} commit={committed:,} | streams_active={stream_count}")
        # Show stream details for running jobs
        if job.get('status') == 'running' and stream_stats:
            for ss in stream_stats:
                sname = ss.get('streamName', '?')
                sstats = ss.get('stats', {})
                sr = sstats.get('recordsEmitted', 0)
                sc = sstats.get('recordsCommitted', 0)
                if sr > 0 or sc > 0:
                    print(f"  {sname}: emitted={sr:,} committed={sc:,}")
