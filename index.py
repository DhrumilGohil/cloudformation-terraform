import boto3
import json
import logging
import time
import datetime
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
      logger.info('Event: ' + str(event))
      ids = []
      dbs = []
      # Create an STS client
      sts = boto3.client('sts')
      # Get the caller identity
      identity = sts.get_caller_identity()
      account_id = identity['Account']
      region = event['region']
      detail = event['detail']
      eventname = detail['eventName']
      arn = event['detail']['userIdentity']['arn']
      principal = event['detail']['userIdentity']['principalId']
      userType = event['detail']['userIdentity']['type']

      if userType == 'IAMUser':
            user = detail['userIdentity']['userName']

      else:
            user = principal.split(':')[1]


      logger.info('principalId: ' + str(principal))
      logger.info('region: ' + str(region))
      logger.info('eventName: ' + str(eventname))
      logger.info('detail: ' + str(detail))

      ec2 = boto3.client('ec2')
      rds = boto3.client('rds')

      if eventname == 'RunInstances':
            items = detail['responseElements']['instancesSet']['items']
            for item in items:
                  ids.append(item['instanceId'])
                  logger.info(ids)

      elif eventname == 'CreateDBInstance':
            bases = detail['requestParameters']['dBInstanceIdentifier']
            for base in bases:
                  dbs.append(base['DBInstanceArn'])

      if ids:
            ec2.create_tags(Resources=ids, Tags=[{'Key': 'User','Value': user}, {'Key': 'AccountID','Value': account_id}, {'Key': 'PrincipalId', 'Value': principal}])

      elif dbs:
            rds.add_tags_to_resource(Resources=dbs, Tags=[{'Key': 'User','Value': user}, {'Key': 'AccountID','Value': account_id}, {'Key': 'PrincipalId', 'Value': principal}])

            
            
      return 'Success'