{% macro databricks__py_write_table(compiled_code, target_relation) %}
{{ compiled_code }}
# --- Autogenerated dbt materialization code. --- #
dbt = dbtObj(spark.table)
df = model(dbt, spark)

import pyspark

{{ py_try_import('pyspark.sql.connect.dataframe', 'newer_pyspark_available') }}
{{ py_try_import('pandas', 'pandas_available') }}
{{ py_try_import('pyspark.pandas', 'pyspark_pandas_api_available') }}
{{ py_try_import('databricks.koalas', 'koalas_available') }}

# preferentially convert pandas DataFrames to pandas-on-Spark or Koalas DataFrames first
# since they know how to convert pandas DataFrames better than `spark.createDataFrame(df)`
# and converting from pandas-on-Spark to Spark DataFrame has no overhead

if pandas_available and isinstance(df, pandas.core.frame.DataFrame):
    if pyspark_pandas_api_available:
        df = pyspark.pandas.frame.DataFrame(df)
    elif koalas_available:
        df = databricks.koalas.frame.DataFrame(df)

# convert to pyspark.sql.dataframe.DataFrame
if isinstance(df, pyspark.sql.dataframe.DataFrame):
    pass  # since it is already a Spark DataFrame
elif newer_pyspark_available and isinstance(df, pyspark.sql.connect.dataframe.DataFrame):
    pass  # since it is already a Spark DataFrame
elif pyspark_pandas_api_available and isinstance(df, pyspark.pandas.frame.DataFrame):
    df = df.to_spark()
elif koalas_available and isinstance(df, databricks.koalas.frame.DataFrame):
    df = df.to_spark()
elif pandas_available and isinstance(df, pandas.core.frame.DataFrame):
    df = spark.createDataFrame(df)
else:
    msg = f"{type(df)} is not a supported type for dbt Python materialization"
    raise Exception(msg)

writer = (
    df.write
        .mode("overwrite")
        .option("overwriteSchema", "true")
{{ py_get_writer_options()|indent(8, True) }}
)

writer.saveAsTable("{{ target_relation }}")
{% endmacro %}

# Note: this is not the code used for performing incremental merges.
# The current process uses this code to create a staging table that is
# merged in using a SQL statement.  To see your incremental config in action,
# look in the dbt.log

{%- macro py_get_writer_options() -%}
{%- set location_root = config.get('location_root', validator=validation.any[basestring]) -%}
{%- set file_format = config.get('file_format', validator=validation.any[basestring])|default('delta', true) -%}
{%- set partition_by = config.get('partition_by', validator=validation.any[list, basestring]) -%}
{%- set liquid_clustered_by = config.get('liquid_clustered_by', validator=validation.any[list, basestring]) -%}
{%- set clustered_by = config.get('clustered_by', validator=validation.any[list, basestring]) -%}
{%- set buckets = config.get('buckets', validator=validation.any[int]) -%}
.format("{{ file_format }}")
{%- if location_root is not none %}
{%- set identifier = model['alias'] %}
{%- if is_incremental() %}
{%- set identifier = identifier + '__dbt_tmp' %}
{%- endif %}
.option("path", "{{ location_root }}/{{ identifier }}")
{%- endif -%}
{%- if partition_by is not none -%}
    {%- if partition_by is string -%}
        {%- set partition_by = [partition_by] -%}
    {%- endif %}
.partitionBy({{ partition_by }})
{%- endif -%}
{%- if liquid_clustered_by -%}
    {%- if liquid_clustered_by is string -%}
        {%- set liquid_clustered_by = [liquid_clustered_by] -%}
    {%- endif %}
.clusterBy({{ liquid_clustered_by }})
{%- endif -%}
{%- if (clustered_by is not none) and (buckets is not none) -%}
    {%- if clustered_by is string -%}
        {%- set clustered_by = [clustered_by] -%}
    {%- endif %}
.bucketBy({{ buckets }}, {{ clustered_by }})
{%- endif -%}
{% endmacro -%}

{% macro py_try_import(library, var_name) -%}
# make sure {{ library }} exists before using it
try:
    import {{ library }}
    {{ var_name }} = True
except ImportError:
    {{ var_name }} = False
{% endmacro %}
