# User Task Template

`user_task.py` must define `run(params)`.

Each line in `params.jsonl` is one independent BOINC workunit. The JSON object
from that line is passed to `run(params)`.

Run the template:

```bash
./scripts/run_experiment.sh --task user --submit-only
```

Run your own task:

```bash
./scripts/run_experiment.sh \
  --task user \
  --user-task path/to/user_task.py \
  --user-params path/to/params.jsonl
```
