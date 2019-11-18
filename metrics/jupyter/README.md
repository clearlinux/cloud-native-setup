# Jupyter image and playbooks

This folder contains tools that enable the metrics report R
ggplot graphs to be loaded into a Jupyter playbook and examined as `plotly`
images. This allows elements (data sets) be be interactively en/disabled in the
graph, as well as selection and zooming of the view. This can aid analysis of
complex and noisy graphs.

# Running the Jupyter

You require `Docker` to run the playbooks. The folder containers a `Dockerfile`,
and will build/install the required Jupyter image, along with the required R libaries
needed to process and display the report graphs.

the playbooks will open and process the `metrics/results` directory, just as the
`report` generator does. The initial processing re-uses the same R scripts from the
`metrics/report/report_dockerfile` directory.

Run the playbooks with:

```bash
$ ./run.sh
```

This will build the Docker image (*Note:* this is a large download), and run the image.
Your shell/prompt will be left 'in' the image. The image output will provide you with a
local URL to open to view the Jupyter.

# Executing the views

Once inside the Jupyter view in your browser, navigate to the `work/k8s-scaling` folder.
Open the `k8s-scaling-rapid.ipynb` playbook file, which should open in a new browser tab.

'Play' the steps in the playbook. You should see one step that generates the `report`
non-interactive graphs, and then further steps that wrap those graphs into interactive
plotly graphs, where you can select which data sets to view (by clicking on their names
in the legend), and zoom in/out (either by click-dragging or by using the plotly dialog
items in the top right hand corner of the view.

# Quitting the Jupyter

Either `docker kill` the docker image running, or `CTRL-C` in the terminal where the docker
image is running, and say `y` when it asks you if you really want to quit.

# Updating the playbooks

If you do update or add to the playbooks, before saving them out in the Jupyter UI, it is
recommended you clear the 'outputs' via the `cell/All Output/Clear' menu option - otherwise
your `.ipynb` file will include encodings for all the images and data you have processed, which
not only bloat the file, but do not really make sense to store in the git source repository.
