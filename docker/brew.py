#!/usr/bin/python3
 
import os
import re
from xmlrpc.client import ServerProxy
import datetime
import logging
import argparse
 
 
def main(args):
    logging.basicConfig(
        format="%(levelname)s - %(asctime)s - %(name)s - %(message)s",
        level=logging.DEBUG
    )
 
    # Print all avaliable arguments passed in.
    logging.info("Working on package: {0}.".format(args.name))
    logging.info("Brew API address: {0}.".format(args.brew_api))
    logging.info("Brew task ID: {0}.".format(args.id))
    logging.info("Build arch: {0}.".format(args.arch))
 
    #API = "http://brewhub.engineering.redhat.com/brewhub"
    URL_PREFIX = "http://download.eng.bos.redhat.com/brewroot/work/"
 
    download_urls = []
    #proxy = ServerProxy(API)
    proxy = ServerProxy(args.brew_api)
 
    sub_tasks = proxy.getTaskChildren(args.id)
    logging.debug("Sub tasks {0}".format(sub_tasks))
 
    for sub_task in sub_tasks:
        if sub_task["arch"] == args.arch and sub_task["method"] == "buildArch":
            sub_task_id = str(sub_task["id"])
            break
    logging.info("Found task ID {0}".format(sub_task_id))
 
    rpms = proxy.getTaskResult(sub_task_id)["rpms"]
    logging.debug("All build RPMS {0}".format(rpms))
 
    for rpm in rpms:
        if args.name.find('kernel')!=-1:
            if args.name in rpm or \
                args.name.replace("kernel", "kernel-core") in rpm or \
                args.name.replace("kernel", "kernel-modules") in rpm:
                    download_urls.append(URL_PREFIX + rpm)
        elif rpm.find('debug')==-1 :
            download_urls.append(URL_PREFIX + rpm)
 
    logging.info("Found RPM {0}".format(download_urls))
 
    print("{0}".format(" ".join(download_urls)))
    #print(" ".join(download_urls))
 
if __name__ == '__main__':
    parser = argparse.ArgumentParser(
            description='Work with brew package'
    )
    parser.add_argument("name", metavar="package-name", type=str,
                        help="package name with format \
                        {name-version-release} or {name} for scratch build")
    parser.add_argument("brew_api", metavar="brew-api", type=str,
                        help="brew API URL")
    parser.add_argument("--id", type=int, required=True, help="brew task ID")
    parser.add_argument("--arch", type=str, help="package arch")
    args = parser.parse_args()
 
    main(args)