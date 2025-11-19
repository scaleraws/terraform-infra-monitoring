import boto3
import os
import time
from datetime import datetime

rds = boto3.client('rds')
ec2 = boto3.client('ec2')

# env vars: RDS_INSTANCE_IDS as comma separated, EC2_INSTANCE_IDS as comma separated
RDS_IDS = os.environ.get('RDS_INSTANCE_IDS','').split(',')
EC2_IDS = os.environ.get('EC2_INSTANCE_IDS','').split(',')
TAG_KEY = os.environ.get('TAG_KEY','CreatedBy')
TAG_VALUE = os.environ.get('TAG_VALUE','lambda-backup')

def create_rds_snapshot(db_instance_id):
    timestamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
    snapshot_id = f"{db_instance_id}-{timestamp}"
    resp = rds.create_db_snapshot(DBSnapshotIdentifier=snapshot_id, DBInstanceIdentifier=db_instance_id)
    # optional: add tags
    try:
        arn = resp['DBSnapshot']['DBSnapshotArn']
        rds.add_tags_to_resource(ResourceName=arn, Tags=[{'Key':TAG_KEY,'Value':TAG_VALUE}])
    except Exception as e:
        print("Tagging RDS snapshot failed:", e)
    return snapshot_id

def create_ebs_snapshots_for_instance(instance_id):
    # find volumes attached to instance
    vols = ec2.describe_volumes(Filters=[{'Name':'attachment.instance-id','Values':[instance_id]}])['Volumes']
    created = []
    for v in vols:
        vol_id = v['VolumeId']
        desc = f"snapshot-{instance_id}-{vol_id}-{int(time.time())}"
        snap = ec2.create_snapshot(VolumeId=vol_id, Description=desc)
        # tag
        ec2.create_tags(Resources=[snap['SnapshotId']], Tags=[{'Key': TAG_KEY, 'Value': TAG_VALUE}])
        created.append(snap['SnapshotId'])
    return created

def lambda_handler(event, context):
    results = {'rds': [], 'ebs': []}
    # RDS snapshots
    for db in filter(None, RDS_IDS):
        try:
            sid = create_rds_snapshot(db)
            results['rds'].append({'db':db,'snapshot':sid})
        except Exception as e:
            print("RDS snapshot error for", db, e)
    # EC2 EBS snapshots
    for inst in filter(None, EC2_IDS):
        try:
            snaps = create_ebs_snapshots_for_instance(inst)
            results['ebs'].append({'instance':inst,'snapshots':snaps})
        except Exception as e:
            print("EBS snapshot error for", inst, e)
    print("Backup results:", results)
    return results
