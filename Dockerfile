FROM swipl:stable
WORKDIR /app
COPY . .
ENV PORT=10000
EXPOSE 10000
CMD ["swipl","/app/server.pl"]
