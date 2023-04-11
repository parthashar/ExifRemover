import boto3
import botocore 

from PIL import Image

s3 = boto3.client('s3')
UPLOAD_BUCKET = 'bucket-b'


def clear_metadata(image_path, newimage_path):
    with Image.open(image_path) as image:
        data = list(image.getdata())
        new_image = Image.new(image.mode, image.size)
        new_image.putdata(data)
        image.save(newimage_path)


def lambda_handler(event, context):
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    download_path = f'/tmp/{key}'
    upload_path = f'/tmp/noexif-{key}'
    try:
        s3.download_file(bucket, key, download_path)
        print("Download Successful")
    except botocore.exceptions.ClientError as e:
        print(f"Download failed from {bucket}, file == {key}")    
        print(e)
    clear_metadata(download_path, upload_path)
    try:
        s3.upload_file(upload_path, UPLOAD_BUCKET, key)
        print(f"Upload to S3:{UPLOAD_BUCKET} Successful ")
    except botocore.exceptions.ClientError as e:
        print(f"Upload Failed, to bucket {UPLOAD_BUCKET}, with File == {key}")
        print(e)
